import json
import logging
import os
import requests
import boto3
import time
import traceback
import uuid
from typing import Any, Dict, Optional, List
from datetime import datetime, timezone

from boto3.dynamodb.conditions import Key


# ==================== STRUCTURED LOGGER ====================

class StructuredLogger:
    """JSON structured logger for Lambda with consistent fields."""

    def __init__(self, name="telegram-bot"):
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.INFO)
        self.logger.handlers = []
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(message)s"))
        self.logger.addHandler(handler)
        self._context = {}

    def set_context(self, **kwargs):
        """Set persistent context fields (request_id, user_id, etc.)."""
        self._context.update(kwargs)

    def clear_context(self):
        """Clear context between invocations."""
        self._context = {}

    def _log(self, level, action, outcome, message="", error=None, **extra):
        entry = {
            "level": level,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "action": action,
            "outcome": outcome,
            "message": message,
        }
        entry.update(self._context)
        entry.update(extra)
        if error:
            entry["error"] = str(error)
            entry["stack_trace"] = traceback.format_exc()
        self.logger.log(
            getattr(logging, level.upper(), logging.INFO),
            json.dumps(entry, default=str),
        )

    def info(self, action, outcome="success", message="", **extra):
        self._log("INFO", action, outcome, message, **extra)

    def warning(self, action, outcome="warning", message="", **extra):
        self._log("WARNING", action, outcome, message, **extra)

    def error(self, action, outcome="failure", message="", error=None, **extra):
        self._log("ERROR", action, outcome, message, error=error, **extra)


logger = StructuredLogger()

TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_API = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}"

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
OLLAMA_API_KEY = os.environ.get("OLLAMA_API_KEY", "")

# DynamoDB setup - use environment variable for region if set
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('chatbot-sessions')
OFFSET_PK = 0
OFFSET_SK = 'last_update_id'

# S3 setup - bucket name can come from environment variable
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', 'chatbot-conversations')
s3_client = boto3.client('s3')
ARCHIVE_BUCKET = S3_BUCKET_NAME
ARCHIVE_PREFIX = 'archives'


def get_last_offset() -> int:
    """Fetch the last processed update_id from DynamoDB (default 0 if none)."""
    try:
        response = table.get_item(Key={'pk': OFFSET_PK, 'sk': OFFSET_SK})
        if 'Item' in response:
            return int(response['Item'].get('last_offset', 0))
    except Exception as e:
        logger.error("get_offset", message="Failed to get offset from DynamoDB", error=e)
    return 0


def save_offset(update_id: int):
    """Save the new last processed update_id to DynamoDB."""
    try:
        table.put_item(
            Item={
                'pk': OFFSET_PK,
                'sk': OFFSET_SK,
                'last_offset': update_id,
                'last_updated_ts': int(time.time())
            }
        )
        logger.info("save_offset", message=f"Saved offset: {update_id}")
    except Exception as e:
        logger.error("save_offset", message="Failed to save offset", error=e)


def poll_messages(offset: int = 0) -> Dict[str, Any]:
    """Poll Telegram getUpdates with offset to avoid reprocessing."""
    if not TELEGRAM_TOKEN:
        return {"ok": False, "error": "TELEGRAM_TOKEN not set"}
    try:
        params = {"limit": 5, "timeout": 0}
        if offset > 0:
            params["offset"] = offset

        logger.info("poll_messages", message=f"Polling with offset: {offset}")
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


def edit_message(chat_id: int, message_id: int, text: str) -> Optional[Dict[str, Any]]:
    """Edit an existing Telegram message."""
    if not TELEGRAM_TOKEN:
        return None
    payload = {"chat_id": chat_id, "message_id": message_id, "text": text}
    try:
        resp = requests.post(f"{TELEGRAM_API}/editMessageText", json=payload, timeout=10)
        return resp.json()
    except Exception:
        return None


def send_document(chat_id: int, file_content: bytes, filename: str, caption: str = "") -> Optional[Dict[str, Any]]:
    """Send a document/file to Telegram chat."""
    if not TELEGRAM_TOKEN:
        return None
    try:
        files = {'document': (filename, file_content, 'application/json')}
        data = {'chat_id': chat_id}
        if caption:
            data['caption'] = caption
        resp = requests.post(f"{TELEGRAM_API}/sendDocument", data=data, files=files, timeout=30)
        return resp.json()
    except Exception as e:
        logger.error("send_document", message="Failed to send document", error=e)
        return None


def get_telegram_file(file_id: str) -> Optional[bytes]:
    """Download a file from Telegram by file_id."""
    if not TELEGRAM_TOKEN:
        return None
    try:
        resp = requests.get(f"{TELEGRAM_API}/getFile", params={"file_id": file_id}, timeout=10)
        data = resp.json()
        if not data.get("ok"):
            logger.warning("get_telegram_file", message="Failed to get file info", response=str(data))
            return None

        file_path = data["result"]["file_path"]
        download_url = f"https://api.telegram.org/file/bot{TELEGRAM_TOKEN}/{file_path}"
        file_resp = requests.get(download_url, timeout=30)
        if file_resp.status_code == 200:
            return file_resp.content
        else:
            logger.error("get_telegram_file", message=f"Failed to download file: {file_resp.status_code}")
            return None
    except Exception as e:
        logger.error("get_telegram_file", message="Error downloading file", error=e)
        return None


def get_user_items(user_id: int) -> List[Dict[str, Any]]:
    """Query all items for a user (sessions)."""
    try:
        response = table.query(
            KeyConditionExpression=Key('pk').eq(user_id)
        )
        return response.get('Items', [])
    except Exception as e:
        logger.error("get_user_items", message=f"Error querying user items for {user_id}", error=e)
        return []


def get_active_session(user_id: int) -> Optional[Dict[str, Any]]:
    """Get the active session for a user."""
    items = get_user_items(user_id)
    for item in items:
        if item.get('is_active', 0) == 1:
            logger.info("get_active_session", message=f"Found active session: {item['sk']}")
            return item
    logger.info("get_active_session", outcome="not_found", message=f"No active session for user {user_id}")
    return None


def create_session(user_id: int, model_name: str = "tinyllama") -> Dict[str, Any]:
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
        'conversation': [],
        'user_id': user_id,
        's3_path': '',
    }
    existing_items = get_user_items(user_id)
    for it in existing_items:
        if it.get('is_active', 0) == 1 and it['sk'] != sk:
            logger.info("create_session", message=f"Deactivating existing session: {it['sk']}")
            table.update_item(
                Key={'pk': user_id, 'sk': it['sk']},
                UpdateExpression='SET is_active = :val',
                ExpressionAttributeValues={':val': 0}
            )
    table.put_item(Item=item)
    logger.info("create_session", message=f"Created new session: {sk}", session_id=session_id)
    return item


def get_current_session(user_id: int) -> Dict[str, Any]:
    """Get active session or create one if none exists."""
    session = get_active_session(user_id)
    if not session:
        logger.info("get_current_session", message="No active session, creating new")
        session = create_session(user_id)
    else:
        logger.info("get_current_session", message="Using existing active session")
    return session


def append_to_conversation(session: Dict[str, Any], message_dict: Dict[str, Any]):
    """Append a message to the session's conversation and update timestamp."""
    session['conversation'].append(message_dict)
    session['last_message_ts'] = int(time.time())
    table.put_item(Item=session)
    logger.info("append_to_conversation", message=f"Conversation length: {len(session['conversation'])}")


def call_ollama(model: str, messages: List[Dict[str, Any]]) -> str:
    """Call Ollama API for chat completion."""
    if not OLLAMA_URL:
        logger.warning("call_ollama", message="OLLAMA_URL not configured")
        return "Ollama URL not configured. Set OLLAMA_URL env var."
    logger.info("call_ollama", message=f"Calling Ollama model '{model}'", context_length=len(messages))
    payload = {
        "model": model,
        "messages": messages,
        "stream": False
    }
    headers = {"X-API-Key": OLLAMA_API_KEY} if OLLAMA_API_KEY else {}
    try:
        resp = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, headers=headers, timeout=45)
        if resp.status_code == 200:
            data = resp.json()
            response_content = data['message']['content']
            logger.info("call_ollama", message=f"Response length {len(response_content)} chars")
            return response_content
        else:
            logger.error("call_ollama", message=f"Ollama API error: {resp.status_code}")
            return f"Sorry, AI response unavailable (error {resp.status_code}). Use /status to check connection."
    except Exception as e:
        logger.error("call_ollama", message="Ollama connection error", error=e)
        return f"Sorry, AI response unavailable (connection error). Use /status to check connection."


# ==================== ARCHIVE FUNCTIONS ====================

def get_archive_s3_key(user_id: int, session_id: str) -> str:
    """Generate S3 key for archived session: archives/{user_id}/{session_id}.json"""
    return f"{ARCHIVE_PREFIX}/{user_id}/{session_id}.json"


def archive_session_to_s3(user_id: int, session: Dict[str, Any]) -> Optional[str]:
    """Archive a session from DynamoDB to S3."""
    session_id = session.get('session_id', '')
    if not session_id:
        logger.error("archive_session", message="Session missing session_id")
        return None

    archive_data = {
        'user_id': user_id,
        'session_id': session_id,
        'model_name': session.get('model_name', 'unknown'),
        'conversation': session.get('conversation', []),
        'original_sk': session.get('sk', ''),
        'last_message_ts': session.get('last_message_ts', 0),
        'archived_at': datetime.utcnow().isoformat() + 'Z',
        'archive_version': '1.0'
    }

    s3_key = get_archive_s3_key(user_id, session_id)

    try:
        s3_client.put_object(
            Bucket=ARCHIVE_BUCKET,
            Key=s3_key,
            Body=json.dumps(archive_data, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'user_id': str(user_id),
                'session_id': session_id,
                'model_name': session.get('model_name', 'unknown')
            }
        )
        logger.info("archive_session", message=f"Archived to s3://{ARCHIVE_BUCKET}/{s3_key}", session_id=session_id)
        return s3_key
    except Exception as e:
        logger.error("archive_session", message="Failed to archive to S3", error=e)
        return None


def delete_session_from_dynamodb(user_id: int, sk: str) -> bool:
    """Delete a session from DynamoDB after archiving."""
    try:
        table.delete_item(Key={'pk': user_id, 'sk': sk})
        logger.info("delete_session", message=f"Deleted session: pk={user_id}, sk={sk}")
        return True
    except Exception as e:
        logger.error("delete_session", message="Failed to delete session", error=e)
        return False


def list_user_archives(user_id: int) -> List[Dict[str, Any]]:
    """List all archived sessions for a user from S3."""
    prefix = f"{ARCHIVE_PREFIX}/{user_id}/"
    archives = []

    try:
        paginator = s3_client.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=ARCHIVE_BUCKET, Prefix=prefix):
            for obj in page.get('Contents', []):
                key = obj['Key']
                session_id = key.split('/')[-1].replace('.json', '')
                archives.append({
                    'session_id': session_id,
                    's3_key': key,
                    'size': obj['Size'],
                    'last_modified': obj['LastModified'].isoformat() if obj.get('LastModified') else ''
                })
        logger.info("list_archives", message=f"Found {len(archives)} archives")
    except Exception as e:
        logger.error("list_archives", message="Failed to list archives", error=e)

    return archives


def get_archive_from_s3(user_id: int, session_id: str) -> Optional[Dict[str, Any]]:
    """Retrieve an archived session from S3."""
    s3_key = get_archive_s3_key(user_id, session_id)

    try:
        response = s3_client.get_object(Bucket=ARCHIVE_BUCKET, Key=s3_key)
        content = response['Body'].read().decode('utf-8')
        return json.loads(content)
    except s3_client.exceptions.NoSuchKey:
        logger.warning("get_archive", outcome="not_found", message=f"Archive not found: {s3_key}")
        return None
    except Exception as e:
        logger.error("get_archive", message="Failed to retrieve archive", error=e)
        return None


def import_archive_to_s3(user_id: int, archive_data: Dict[str, Any]) -> Optional[str]:
    """Import an archive file to S3 for a user."""
    new_session_id = str(uuid.uuid4())

    imported_data = {
        'user_id': user_id,
        'session_id': new_session_id,
        'model_name': archive_data.get('model_name', 'imported'),
        'conversation': archive_data.get('conversation', []),
        'original_session_id': archive_data.get('session_id', 'unknown'),
        'original_user_id': archive_data.get('user_id', 'unknown'),
        'last_message_ts': archive_data.get('last_message_ts', 0),
        'archived_at': archive_data.get('archived_at', datetime.utcnow().isoformat() + 'Z'),
        'imported_at': datetime.utcnow().isoformat() + 'Z',
        'archive_version': '1.0'
    }

    s3_key = get_archive_s3_key(user_id, new_session_id)

    try:
        s3_client.put_object(
            Bucket=ARCHIVE_BUCKET,
            Key=s3_key,
            Body=json.dumps(imported_data, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'user_id': str(user_id),
                'session_id': new_session_id,
                'imported': 'true'
            }
        )
        logger.info("import_archive", message=f"Imported to s3://{ARCHIVE_BUCKET}/{s3_key}")
        return new_session_id
    except Exception as e:
        logger.error("import_archive", message="Failed to import archive", error=e)
        return None


# ==================== COMMAND HANDLERS ====================

def handle_command(cmd: str, payload: str, chat_id: int, user_id: int, update_id: int) -> str:
    """Handle bot commands."""
    logger.info("handle_command", message=f"Command: {cmd}", command=cmd)

    if cmd == "/start" or cmd == "/hello":
        session = get_current_session(user_id)
        resp = f"Hello! Your current model is {session['model_name']}. Chat away or use /help."
        send_message(chat_id, resp)
        return "start_or_hello"

    if cmd == "/help":
        resp = """Commands:
/start or /hello - Greeting and session init
/newsession - Start a new chat session
/listsessions - List your sessions
/switch <number> - Switch to a session (e.g., /switch 1)
/history - Show recent messages in current session
/status - Check system and Ollama status
/echo <text> - Echo back text

Archive Commands:
/archive - List sessions to archive
/archive <number> - Archive a specific session to S3
/listarchives - List your archived sessions
/export <number> - Export an archive as a file
(Send a JSON file to import an archive)

Send any text message to chat with the AI model."""
        send_message(chat_id, resp)
        return "help"

    if cmd == "/status":
        ollama_status = "unknown"
        try:
            status_headers = {"X-API-Key": OLLAMA_API_KEY} if OLLAMA_API_KEY else {}
            check = requests.get(f"{OLLAMA_URL}/api/tags", headers=status_headers, timeout=5)
            if check.status_code == 200:
                models = [m["name"] for m in check.json().get("models", [])]
                ollama_status = f"connected, models: {', '.join(models) if models else 'none loaded'}"
            else:
                ollama_status = f"error (HTTP {check.status_code})"
        except Exception:
            ollama_status = "unreachable (instance may be stopped)"
        resp_msg = f"Bot: running on AWS\nOllama: {ollama_status}\nEndpoint: {OLLAMA_URL}"
        send_message(chat_id, resp_msg)
        logger.info("handle_command", message="Status check", ollama_status=ollama_status)
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
            msg_count = len(session.get('conversation', []))
            msg += f"{i+1}. {model} ({sid}){active} - {msg_count} msgs - Last: {ts_str}\n"
        send_message(chat_id, msg)
        return "listsessions"

    if cmd == "/switch":
        try:
            idx = int(payload.strip()) - 1
            items = get_user_items(user_id)
            sessions = [it for it in items if it['sk'].startswith('MODEL#')]
            if 0 <= idx < len(sessions):
                target_sk = sessions[idx]['sk']
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
        conversation = session.get('conversation', [])
        if isinstance(conversation, str):
            try:
                conversation = json.loads(conversation)
            except:
                conversation = []

        conv = conversation[-5:] if conversation else []
        if not conv:
            send_message(chat_id, "No messages in this session yet.")
            return "no_history"
        msg = "Recent conversation:\n"
        for m in conv:
            role = m.get('role', 'unknown').capitalize()
            content = m.get('content', '')
            content = (content[:100] + "...") if len(content) > 100 else content
            ts = m.get('ts', int(time.time()))
            ts_str = time.strftime('%H:%M', time.localtime(ts))
            msg += f"{role} ({ts_str}): {content}\n"
        send_message(chat_id, msg)
        return "history"

    if cmd == "/echo":
        resp = payload.strip() if payload.strip() else "Usage: /echo <text>"
        send_message(chat_id, resp)
        return "echo"

    # ==================== ARCHIVE COMMANDS ====================

    if cmd == "/archive":
        items = get_user_items(user_id)
        sessions = [it for it in items if it['sk'].startswith('MODEL#')]

        if not sessions:
            send_message(chat_id, "No sessions to archive. Start chatting first!")
            return "no_sessions_to_archive"

        if not payload.strip():
            msg = "Sessions available to archive:\n"
            for i, session in enumerate(sessions):
                active = " (active)" if session.get('is_active', 0) == 1 else ""
                model = session['model_name']
                sid = session['session_id'][:8]
                msg_count = len(session.get('conversation', []))
                ts_str = time.strftime('%Y-%m-%d %H:%M', time.localtime(session.get('last_message_ts', 0)))
                msg += f"{i+1}. {model} ({sid}){active} - {msg_count} msgs - {ts_str}\n"
            msg += "\nUse /archive <number> to archive a session (e.g., /archive 1)"
            send_message(chat_id, msg)
            return "list_for_archive"

        try:
            idx = int(payload.strip()) - 1
            if 0 <= idx < len(sessions):
                session = sessions[idx]
                session_id = session['session_id']

                s3_key = archive_session_to_s3(user_id, session)
                if not s3_key:
                    send_message(chat_id, "Failed to archive session to S3. Please try again.")
                    return "archive_s3_error"

                if delete_session_from_dynamodb(user_id, session['sk']):
                    msg_count = len(session.get('conversation', []))
                    resp = f"Session archived successfully!\n"
                    resp += f"- Model: {session['model_name']}\n"
                    resp += f"- Messages: {msg_count}\n"
                    resp += f"- Archive ID: {session_id[:8]}\n"
                    resp += f"\nUse /listarchives to see your archives."
                    send_message(chat_id, resp)
                    return "archived"
                else:
                    send_message(chat_id, "Session saved to S3 but failed to remove from active storage.")
                    return "archive_cleanup_error"
            else:
                send_message(chat_id, "Invalid session number. Use /archive to see available sessions.")
                return "invalid_archive_number"
        except ValueError:
            send_message(chat_id, "Usage: /archive <number> (e.g., /archive 1)")
            return "invalid_archive_format"

    if cmd == "/listarchives":
        archives = list_user_archives(user_id)

        if not archives:
            send_message(chat_id, "No archived sessions yet. Use /archive to archive a session.")
            return "no_archives"

        msg = "Your archived sessions:\n"
        for i, archive in enumerate(archives):
            sid = archive['session_id'][:8]
            size_kb = archive['size'] / 1024
            last_mod = archive.get('last_modified', 'N/A')[:10]
            msg += f"{i+1}. Archive {sid} - {size_kb:.1f}KB - {last_mod}\n"
        msg += "\nUse /export <number> to download an archive."
        send_message(chat_id, msg)
        return "listarchives"

    if cmd == "/export":
        if not payload.strip():
            send_message(chat_id, "Usage: /export <number> (e.g., /export 1)\nUse /listarchives to see available archives.")
            return "export_no_number"

        archives = list_user_archives(user_id)

        if not archives:
            send_message(chat_id, "No archived sessions to export. Use /archive first.")
            return "no_archives_to_export"

        try:
            idx = int(payload.strip()) - 1
            if 0 <= idx < len(archives):
                archive_info = archives[idx]
                session_id = archive_info['session_id']

                archive_data = get_archive_from_s3(user_id, session_id)
                if not archive_data:
                    send_message(chat_id, "Failed to retrieve archive. Please try again.")
                    return "export_retrieve_error"

                filename = f"archive_{session_id[:8]}_{archive_data.get('model_name', 'chat')}.json"
                file_content = json.dumps(archive_data, indent=2, default=str).encode('utf-8')

                msg_count = len(archive_data.get('conversation', []))
                caption = f"Archive: {archive_data.get('model_name', 'unknown')} - {msg_count} messages"

                result = send_document(chat_id, file_content, filename, caption)
                if result and result.get('ok'):
                    send_message(chat_id, "Archive exported! You can send this file back to import it later.")
                    return "exported"
                else:
                    send_message(chat_id, "Failed to send archive file. Please try again.")
                    return "export_send_error"
            else:
                send_message(chat_id, "Invalid archive number. Use /listarchives to see available archives.")
                return "invalid_export_number"
        except ValueError:
            send_message(chat_id, "Usage: /export <number> (e.g., /export 1)")
            return "invalid_export_format"

    send_message(chat_id, "Unknown command. Send /help for available commands.")
    return "unknown"


def handle_document(document: Dict[str, Any], chat_id: int, user_id: int) -> str:
    """Handle incoming document (file) - for archive imports."""
    file_name = document.get('file_name', '')
    file_id = document.get('file_id', '')
    mime_type = document.get('mime_type', '')

    logger.info("handle_document", message=f"Received document: {file_name} ({mime_type})")

    if not (file_name.endswith('.json') or mime_type == 'application/json'):
        send_message(chat_id, "Please send a JSON file to import an archive.\nExport archives using /export to get the correct format.")
        return "invalid_file_type"

    file_content = get_telegram_file(file_id)
    if not file_content:
        send_message(chat_id, "Failed to download file. Please try again.")
        return "download_error"

    try:
        archive_data = json.loads(file_content.decode('utf-8'))
    except json.JSONDecodeError as e:
        send_message(chat_id, f"Invalid JSON file. Please send a valid archive export.\nError: {str(e)[:100]}")
        return "json_parse_error"

    if 'conversation' not in archive_data:
        send_message(chat_id, "Invalid archive format. Missing 'conversation' field.\nUse /export to get a valid archive format.")
        return "invalid_archive_format"

    new_session_id = import_archive_to_s3(user_id, archive_data)
    if not new_session_id:
        send_message(chat_id, "Failed to import archive. Please try again.")
        return "import_error"

    msg_count = len(archive_data.get('conversation', []))
    original_model = archive_data.get('model_name', 'unknown')

    resp = f"Archive imported successfully!\n"
    resp += f"- Original model: {original_model}\n"
    resp += f"- Messages: {msg_count}\n"
    resp += f"- New archive ID: {new_session_id[:8]}\n"
    resp += f"\nUse /listarchives to see your archives."
    send_message(chat_id, resp)
    return "imported"


def handle_message(text: str, chat_id: int, user_id: int, update_id: int, document: Optional[Dict[str, Any]] = None) -> str:
    """Handle incoming messages: commands, chat, or documents."""

    if document:
        return handle_document(document, chat_id, user_id)

    if not text:
        send_message(chat_id, "No text received.")
        return "no_text"

    text = text.strip()
    if not text:
        send_message(chat_id, "No text received.")
        return "no_text"

    MAX_MESSAGE_LENGTH = 4000
    if len(text) > MAX_MESSAGE_LENGTH:
        send_message(chat_id, f"Message too long ({len(text)} chars). Max is {MAX_MESSAGE_LENGTH}.")
        return "message_too_long"

    logger.info("handle_message", message=f"Processing text message", update_id=update_id)

    if text.startswith('/'):
        parts = text.split(" ", 1)
        cmd = parts[0].split("@", 1)[0].lower()
        payload = parts[1] if len(parts) > 1 else ""
        return handle_command(cmd, payload, chat_id, user_id, update_id)
    else:
        session = get_current_session(user_id)
        now = int(time.time())

        # Check if a request is already being processed (within last 55 seconds)
        pending_since = session.get("pending_request_ts", 0)
        if pending_since and (now - pending_since) < 55:
            send_message(chat_id, "Please wait, still generating a response to your previous message...")
            return "rate_limited"

        user_msg = {"role": "user", "content": text, "ts": now}
        append_to_conversation(session, user_msg)

        # Mark request as pending
        session['pending_request_ts'] = now
        table.put_item(Item=session)

        # Send "Thinking..." message so user knows the bot is working
        thinking_resp = send_message(chat_id, "Thinking...")
        thinking_msg_id = None
        if thinking_resp and thinking_resp.get("ok"):
            thinking_msg_id = thinking_resp["result"]["message_id"]

        # Build conversation context for Ollama (strip ts field, limit to last 10 messages)
        all_msgs = [
            {"role": m["role"], "content": m["content"]}
            for m in session.get("conversation", [])
            if "role" in m and "content" in m
        ]
        messages = all_msgs[-10:]

        # Call Ollama for AI response
        model_name = session.get("model_name", "tinyllama")
        ai_response = call_ollama(model_name, messages)

        # Clear pending flag
        session['pending_request_ts'] = 0
        ass_msg = {"role": "assistant", "content": ai_response, "ts": int(time.time())}
        append_to_conversation(session, ass_msg)

        # Replace "Thinking..." with the actual response
        if thinking_msg_id:
            edit_message(chat_id, thinking_msg_id, ai_response)
        else:
            send_message(chat_id, ai_response)
        return "ai_response"


def process_telegram_update(update: Dict[str, Any]) -> Dict[str, Any]:
    """Process a single Telegram update (from webhook or polling)."""
    update_id = update.get("update_id", 0)
    message = update.get("message")
    
    if not message:
        logger.warning("process_update", outcome="skipped", message=f"No message in update_id={update_id}")
        return {"processed": False, "reason": "no_message"}

    chat_id = message.get("chat", {}).get("id")
    from_user = message.get('from', {})
    user_id = from_user.get('id', chat_id)
    text = message.get("text", "")
    document = message.get("document")

    # Set context for all subsequent log entries in this request
    logger.set_context(user_id=user_id, message_id=update_id, chat_id=chat_id)

    if chat_id is None:
        logger.warning("process_update", outcome="skipped", message="No chat_id in update")
        return {"processed": False, "reason": "no_chat_id"}

    # Deduplicate: check if this update_id was already processed
    try:
        dedup_resp = table.get_item(Key={'pk': OFFSET_PK, 'sk': f'update#{update_id}'})
        if 'Item' in dedup_resp:
            logger.info("process_update", outcome="skipped", message=f"Duplicate update_id={update_id}")
            return {"processed": False, "reason": "duplicate"}
        # Mark this update_id as processed
        table.put_item(Item={'pk': OFFSET_PK, 'sk': f'update#{update_id}', 'ts': int(time.time())})
    except Exception:
        pass  # If dedup check fails, process anyway

    handle_result = handle_message(text, chat_id, user_id, update_id, document)

    return {
        "processed": True,
        "update_id": update_id,
        "handled": handle_result,
        "text": text if text else "(document)",
        "user_id": user_id
    }


def lambda_handler(event, context):
    """
    Main Lambda handler.
    Supports both:
    1. Webhook mode (API Gateway triggers Lambda with Telegram update in body)
    2. Polling mode (Manual invocation to poll Telegram getUpdates)
    """
    # Set request context from Lambda context
    request_id = getattr(context, 'aws_request_id', 'unknown') if context else 'unknown'
    logger.clear_context()
    logger.set_context(request_id=request_id)

    logger.info("lambda_handler", message="Event received", mode="webhook" if 'body' in event else "polling")

    # Check if this is a webhook request from API Gateway
    if 'body' in event:
        # API Gateway webhook mode
        try:
            body = event.get('body', '{}')
            if isinstance(body, str):
                update = json.loads(body)
            else:
                update = body

            logger.info("webhook", message="Processing webhook update", update_id=update.get("update_id", 0))

            result = process_telegram_update(update)

            # Always return 200 to Telegram to acknowledge receipt
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"ok": True, "result": result})
            }
        except json.JSONDecodeError as e:
            logger.error("webhook", message="Invalid JSON in request body", error=e)
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"ok": False, "error": "Invalid JSON"})
            }
        except Exception as e:
            logger.error("webhook", message="Unhandled webhook error", error=e)
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"ok": False, "error": str(e)})
            }
    
    # Polling mode (manual invocation or scheduled)
    try:
        last_offset = get_last_offset()
        logger.info("polling", message=f"Starting with last_offset: {last_offset}")

        if last_offset == 0:
            logger.info("polling", message="First run detected")
            initial_poll = poll_messages(0)
            if initial_poll.get("ok"):
                all_updates = initial_poll.get("result", [])
                if all_updates:
                    latest_update = all_updates[-1]
                    latest_id = latest_update.get("update_id", 0)

                    if len(all_updates) > 1:
                        logger.info("polling", message=f"Skipping {len(all_updates) - 1} old messages")

                    result = process_telegram_update(latest_update)
                    save_offset(latest_id + 1)
                    return {
                        "statusCode": 200,
                        "body": {
                            "mode": "polling",
                            "first_run": True,
                            "result": result,
                            "skipped_count": len(all_updates) - 1
                        }
                    }

                save_offset(latest_id + 1 if all_updates else 1)
                return {
                    "statusCode": 200,
                    "body": f"First run: Cleared {len(all_updates)} old messages"
                }

        result = poll_messages(last_offset)

        if not result.get("ok"):
            error_msg = f"Telegram API error: {result.get('error', result)}"
            logger.error("polling", message=error_msg)
            return {"statusCode": 400, "body": error_msg}

        updates = result.get("result", [])

        if not updates:
            logger.info("polling", outcome="no_messages", message="No new messages")
            return {"statusCode": 200, "body": "No messages"}

        logger.info("polling", message=f"Received {len(updates)} updates")

        processed = []
        max_update_id = last_offset

        for update in updates:
            update_id = update.get("update_id", 0)

            if last_offset > 0 and update_id < last_offset:
                logger.info("polling", outcome="skipped", message=f"Already processed update_id={update_id}")
                max_update_id = max(max_update_id, update_id)
                continue

            result = process_telegram_update(update)
            if result.get("processed"):
                processed.append(result)
            max_update_id = max(max_update_id, update_id)

        if max_update_id >= last_offset:
            new_offset = max_update_id + 1
            save_offset(new_offset)
            logger.info("polling", message=f"Acknowledged up to update_id={max_update_id}, next offset={new_offset}")

        return {
            "statusCode": 200,
            "body": {
                "mode": "polling",
                "processed_count": len(processed),
                "messages": processed,
                "last_offset": last_offset,
                "new_offset": max_update_id + 1
            }
        }
    except Exception as e:
        logger.error("lambda_handler", message="Unhandled error in polling mode", error=e)
        return {"statusCode": 500, "body": str(e)}
