import json
import os
import requests
import boto3
import time
import uuid
from typing import Any, Dict, Optional, List

from boto3.dynamodb.conditions import Key

TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_API = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}"

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")

# DynamoDB setup for offset tracking and sessions (uses the existing chatbot-sessions table)
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('chatbot-sessions')
OFFSET_PK = 0  # Number 0 for global bot state (matches pk type "N")
OFFSET_SK = 'last_update_id'

def get_last_offset() -> int:
    """Fetch the last processed update_id from DynamoDB (default 0 if none)."""
    try:
        response = table.get_item(Key={'pk': OFFSET_PK, 'sk': OFFSET_SK})
        if 'Item' in response:
            return int(response['Item'].get('last_offset', 0))
    except Exception as e:
        print(f"Error getting offset: {e}")
    return 0

def save_offset(update_id: int):
    """Save the new last processed update_id to DynamoDB."""
    try:
        table.put_item(
            Item={
                'pk': OFFSET_PK,
                'sk': OFFSET_SK,
                'last_offset': update_id,
                'last_updated_ts': int(time.time())  # Unix timestamp
            }
        )
        print(f"Saved offset: {update_id}")
    except Exception as e:
        print(f"Error saving offset: {e}")

def poll_messages(offset: int = 0) -> Dict[str, Any]:
    """Poll Telegram getUpdates with offset to avoid reprocessing."""
    if not TELEGRAM_TOKEN:
        return {"ok": False, "error": "TELEGRAM_TOKEN not set"}
    try:
        params = {"limit": 5, "timeout": 0}
        if offset > 0:
            params["offset"] = offset
        
        print(f"Polling with offset: {offset}")
        resp = requests.get(f"{TELEGRAM_API}/getUpdates", params=params, timeout=10)
        return resp.json()
    except Exception as e:
        return {"ok": False, "error": str(e)}

def send_message(chat_id: int, text: str) -> Optional[Dict[str, Any]]:
    """Send a message back to Telegram."""
    if not TELEGRAM_TOKEN:
        return None
    payload = {"chat_id": chat_id, "text": text}
    try:
        resp = requests.post(f"{TELEGRAM_API}/sendMessage", json=payload, timeout=10)
        return resp.json()
    except Exception:
        return None

def get_user_items(user_id: int) -> List[Dict[str, Any]]:
    """Query all items for a user (sessions)."""
    try:
        response = table.query(
            KeyConditionExpression=Key('pk').eq(user_id)
        )
        return response.get('Items', [])
    except Exception as e:
        print(f"Error querying user items for {user_id}: {e}")
        return []

def get_active_session(user_id: int) -> Optional[Dict[str, Any]]:
    """Get the active session for a user."""
    items = get_user_items(user_id)
    for item in items:
        if item.get('is_active', 0) == 1:
            print(f"Found active session for user {user_id}: {item['sk']}")
            return item
    print(f"No active session found for user {user_id}")
    return None

def create_session(user_id: int, model_name: str = "llama3") -> Dict[str, Any]:
    """Create a new session, deactivate old active ones."""
    session_id = str(uuid.uuid4())
    sk = f"MODEL#{model_name}#SESSION#{session_id}"
    now = int(time.time())
    item = {
        'pk': user_id,
        'sk': sk,
        'model_name': model_name,
        'session_id': session_id,
        'is_active': 1,
        'last_message_ts': now,
        'conversation': [],  # List of {"role": "user"/"assistant", "content": str, "ts": int}
        'user_id': user_id,
    }
    # Deactivate any existing active sessions
    existing_items = get_user_items(user_id)
    for it in existing_items:
        if it.get('is_active', 0) == 1 and it['sk'] != sk:  # Avoid self-deactivation if somehow duplicate
            print(f"Deactivating existing session for user {user_id}: {it['sk']}")
            table.update_item(
                Key={'pk': user_id, 'sk': it['sk']},
                UpdateExpression='SET is_active = :val',
                ExpressionAttributeValues={':val': 0}
            )
    # Put new session
    table.put_item(Item=item)
    print(f"Created new session for user {user_id}: {sk}")
    return item

def get_current_session(user_id: int) -> Dict[str, Any]:
    """Get active session or create one if none exists."""
    session = get_active_session(user_id)
    if not session:
        print(f"No active session, creating new for user {user_id}")
        session = create_session(user_id)
    else:
        print(f"Using existing active session for user {user_id}")
    return session

def append_to_conversation(session: Dict[str, Any], message_dict: Dict[str, Any]):
    """Append a message to the session's conversation and update timestamp."""
    session['conversation'].append(message_dict)
    session['last_message_ts'] = int(time.time())
    # Put the full updated session back
    table.put_item(Item=session)
    print(f"Appended message to session {session['sk']}, conversation length: {len(session['conversation'])}")

def call_ollama(model: str, messages: List[Dict[str, Any]]) -> str:
    """Call Ollama API for chat completion."""
    if not OLLAMA_URL:
        print("OLLAMA_URL not configured.")
        return "Ollama URL not configured. Set OLLAMA_URL env var."
    print(f"Calling Ollama at {OLLAMA_URL} with model '{model}' (context length: {len(messages)})")
    payload = {
        "model": model,
        "messages": messages,
        "stream": False
    }
    try:
        resp = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=60)
        if resp.status_code == 200:
            data = resp.json()
            response_content = data['message']['content']
            print(f"Ollama success: Response length {len(response_content)} chars")
            return response_content
        else:
            print(f"Ollama API error: {resp.status_code} - {resp.text}")
            return f"Sorry, AI response unavailable (error {resp.status_code}). Use /status to check connection."
    except Exception as e:
        print(f"Ollama call error: {e}")
        return f"Sorry, AI response unavailable (connection error). Use /status to check connection."

def handle_command(cmd: str, payload: str, chat_id: int, user_id: int, update_id: int) -> str:
    """Handle bot commands."""
    print(f"Handling command '{cmd}' for user {user_id} in chat {chat_id}")

    if cmd == "/start" or cmd == "/hello":
        session = get_current_session(user_id)
        resp = f"Hello! 👋 Your current model is {session['model_name']}. Chat away or use /help."
        send_message(chat_id, resp)
        return "start_or_hello"

    if cmd == "/help":
        resp = """Commands:
/start or /hello - Greeting and session init
/newsession - Start a new chat session
/listsessions - List your sessions
/switch <number> - Switch to a session (e.g., /switch 1)
/history - Show recent messages in current session
/status - Check Ollama AI connection and models
/echo <text> - Echo back text"""
        send_message(chat_id, resp)
        return "help"

    if cmd == "/status":
        try:
            print(f"Checking Ollama status at {OLLAMA_URL}")
            resp = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                models = data.get('models', [])
                if models:
                    model_list = "\n".join([f"- {m['name']}" for m in models])
                    resp_msg = f"✅ Ollama connected! Available models:\n{model_list}"
                else:
                    resp_msg = "✅ Ollama connected, but no models pulled yet. Run `ollama pull <model>` on host."
            else:
                resp_msg = f"❌ Ollama API error: {resp.status_code}. Check if Ollama is running on host:11434."
        except Exception as e:
            resp_msg = f"❌ Ollama connection failed: {str(e)}. Ensure Ollama is running and accessible from Docker."
        send_message(chat_id, resp_msg)
        return "status"

    if cmd == "/newsession":
        new_session = create_session(user_id)
        resp = f"New session created with model '{new_session['model_name']}' (ID: {new_session['session_id'][:8]})."
        send_message(chat_id, resp)
        return "newsession"

    if cmd == "/listsessions":
        items = get_user_items(user_id)
        sessions = [it for it in items if it['sk'].startswith('MODEL#')]
        if not sessions:
            send_message(chat_id, "No sessions yet. Start chatting or use /newsession.")
            return "no_sessions"
        msg = "Your sessions:\n"
        for i, session in enumerate(sessions):
            active = " (active)" if session.get('is_active', 0) == 1 else ""
            model = session['model_name']
            sid = session['session_id'][:8]
            ts_str = time.strftime('%Y-%m-%d %H:%M', time.localtime(session.get('last_message_ts', 0)))
            msg += f"{i+1}. {model} ({sid}){active} - Last: {ts_str}\n"
        send_message(chat_id, msg)
        return "listsessions"

    if cmd == "/switch":
        try:
            idx = int(payload.strip()) - 1
            items = get_user_items(user_id)
            sessions = [it for it in items if it['sk'].startswith('MODEL#')]
            if 0 <= idx < len(sessions):
                target_sk = sessions[idx]['sk']
                # Update all sessions: set target to active, others inactive
                for session in sessions:
                    val = 1 if session['sk'] == target_sk else 0
                    table.update_item(
                        Key={'pk': user_id, 'sk': session['sk']},
                        UpdateExpression='SET is_active = :val',
                        ExpressionAttributeValues={':val': val}
                    )
                model = sessions[idx]['model_name']
                resp = f"Switched to session {idx+1} (model: {model})."
                send_message(chat_id, resp)
                return "switch"
            else:
                send_message(chat_id, "Invalid session number. Use /listsessions.")
                return "invalid_switch"
        except ValueError:
            send_message(chat_id, "Usage: /switch <number> (e.g., /switch 1)")
            return "invalid_switch"

    if cmd == "/history":
        session = get_current_session(user_id)
        conv = session['conversation'][-5:]  # Last 5 messages
        if not conv:
            send_message(chat_id, "No messages in this session yet.")
            return "no_history"
        msg = "Recent conversation:\n"
        for m in conv:
            role = m['role'].capitalize()
            content = (m['content'][:100] + "...") if len(m['content']) > 100 else m['content']
            ts_str = time.strftime('%H:%M', time.localtime(m['ts']))
            msg += f"{role} ({ts_str}): {content}\n"
        send_message(chat_id, msg)
        return "history"

    if cmd == "/echo":
        resp = payload.strip() if payload.strip() else "Usage: /echo <text>"
        send_message(chat_id, resp)
        return "echo"

    # Unknown command
    send_message(chat_id, "Unknown command. Send /help for available commands.")
    return "unknown"

def handle_message(text: str, chat_id: int, user_id: int, update_id: int) -> str:
    """Handle incoming messages: commands or chat."""
    if not text:
        send_message(chat_id, "No text received.")
        return "no_text"

    # Normalize and trim
    text = text.strip()
    if not text:
        send_message(chat_id, "No text received.")
        return "no_text"

    print(f"Processing update_id={update_id}, text='{text}' for user {user_id} in chat {chat_id}")

    if text.startswith('/'):
        # Command
        parts = text.split(" ", 1)
        cmd = parts[0].split("@", 1)[0].lower()
        payload = parts[1] if len(parts) > 1 else ""
        return handle_command(cmd, payload, chat_id, user_id, update_id)
    else:
        # Chat message: process with AI
        session = get_current_session(user_id)
        model = session['model_name']
        now = int(time.time())
        user_msg = {"role": "user", "content": text, "ts": now}
        append_to_conversation(session, user_msg)

        # Prepare messages for Ollama (exclude ts)
        messages_for_ollama = [{"role": m['role'], "content": m['content']} for m in session['conversation']]

        response = call_ollama(model, messages_for_ollama)

        ass_msg = {"role": "assistant", "content": response, "ts": int(time.time())}
        append_to_conversation(session, ass_msg)
        send_message(chat_id, response)

        return "chat_message"

def lambda_handler(event, context):
    """Main Lambda handler. Process all pending messages from Telegram."""
    try:
        last_offset = get_last_offset()
        print(f"Starting with last_offset: {last_offset}")
        
        # FIRST RUN INITIALIZATION: Process only the most recent message
        if last_offset == 0:
            print("First run detected - will process only the latest message")
            initial_poll = poll_messages(0)
            if initial_poll.get("ok"):
                all_updates = initial_poll.get("result", [])
                if all_updates:
                    # Process only the LAST (most recent) message
                    latest_update = all_updates[-1]
                    latest_id = latest_update.get("update_id", 0)
                    
                    # Skip all older messages
                    if len(all_updates) > 1:
                        print(f"Skipping {len(all_updates) - 1} old messages")
                    
                    # Process the latest one
                    message = latest_update.get("message")
                    if message:
                        chat_id = message.get("chat", {}).get("id")
                        from_user = message.get('from', {})
                        user_id = from_user.get('id', chat_id)  # Fallback to chat_id if no from
                        text = message.get("text", "")
                        if chat_id:
                            handle_result = handle_message(text, chat_id, user_id, latest_id)
                            save_offset(latest_id + 1)
                            return {
                                "statusCode": 200,
                                "body": {
                                    "first_run": True,
                                    "processed": handle_result,
                                    "text": text,
                                    "user_id": user_id,
                                    "skipped_count": len(all_updates) - 1
                                }
                            }
                    
                    # No message to process, just skip all
                    save_offset(latest_id + 1)
                    return {
                        "statusCode": 200,
                        "body": f"First run: Cleared {len(all_updates)} old messages"
                    }
        
        result = poll_messages(last_offset)
        
        if not result.get("ok"):
            error_msg = f"Telegram API error: {result.get('error', result)}"
            print(error_msg)
            return {"statusCode": 400, "body": error_msg}
        
        updates = result.get("result", [])
        
        if not updates:
            print("No new messages")
            return {"statusCode": 200, "body": "No messages"}

        print(f"Received {len(updates)} updates")

        # Process all NEW messages (those we haven't seen yet)
        processed = []
        max_update_id = last_offset
        
        for update in updates:
            update_id = update.get("update_id", 0)
            
            # Skip if we've already processed this update
            if last_offset > 0 and update_id < last_offset:
                print(f"Skipping already-processed update_id={update_id}")
                max_update_id = max(max_update_id, update_id)
                continue
            
            message = update.get("message")
            if not message:
                print(f"No message in update_id={update_id}, skipping")
                max_update_id = max(max_update_id, update_id)
                continue
            
            chat_id = message.get("chat", {}).get("id")
            from_user = message.get('from', {})
            user_id = from_user.get('id', chat_id)  # Use from.id primarily, fallback to chat_id for private chats
            text = message.get("text", "")
            
            if chat_id is not None:
                handle_result = handle_message(text, chat_id, user_id, update_id)
                processed.append({
                    "update_id": update_id,
                    "handled": handle_result,
                    "text": text,
                    "user_id": user_id
                })
                max_update_id = max(max_update_id, update_id)
        
        # CRITICAL: Save offset to acknowledge we've processed these messages
        if max_update_id >= last_offset:
            new_offset = max_update_id + 1
            save_offset(new_offset)
            print(f"Acknowledged up to update_id={max_update_id}, next offset={new_offset}")
        
        return {
            "statusCode": 200, 
            "body": {
                "processed_count": len(processed), 
                "messages": processed,
                "last_offset": last_offset,
                "new_offset": max_update_id + 1
            }
        }
    except Exception as e:
        error_msg = f"Error: {str(e)}"
        print(error_msg)
        return {"statusCode": 500, "body": error_msg}ssssssss