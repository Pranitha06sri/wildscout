"""Minimal direct Ollama probe; no FastAPI or image-library overhead."""
import argparse
import base64
import http.client
import json
import struct
import sys
import time
import zlib


def tiny_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + b'\x20\xa0\x30' * 32 for _ in range(32))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 32, 32, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def metadata(path):
    started = time.perf_counter()
    connection = http.client.HTTPConnection('127.0.0.1', 11434, timeout=15)
    try:
        connection.request('GET', path)
        response = connection.getresponse()
        print(json.dumps({'path': path, 'status': response.status,
                          'body': json.loads(response.read()),
                          'seconds': round(time.perf_counter() - started, 3)}), flush=True)
    except Exception as error:
        print(json.dumps({'path': path, 'error': str(error), 'seconds': round(time.perf_counter()-started, 3)}), flush=True)
    finally:
        connection.close()


def inference(text_only, timeout, no_think, prefill):
    message = {'role': 'user', 'content': 'Reply with one word: green.' if text_only else 'What color? One word.'}
    if not text_only:
        message['images'] = [base64.b64encode(tiny_png()).decode('ascii')]
    payload = {'model': 'qwen3-vl:2b', 'messages': [message], 'stream': True,
               'options': {'temperature': 0, 'num_predict': 16}}
    if no_think:
        payload['think'] = False
    if prefill:
        message['content'] += ' /no_think'
        payload['messages'].append({'role': 'assistant', 'content': '<think>\n\n</think>\n\n'})
    started = time.perf_counter()
    connection = http.client.HTTPConnection('127.0.0.1', 11434, timeout=timeout)
    content = ''
    thinking_tokens = 0
    try:
        connection.request('POST', '/api/chat', json.dumps(payload), {'Content-Type': 'application/json'})
        response = connection.getresponse()
        print(json.dumps({'inference_status': response.status, 'headers_seconds': round(time.perf_counter()-started, 3),
                          'text_only': text_only, 'image_bytes': 0 if text_only else len(tiny_png())}), flush=True)
        while True:
            line = response.readline()
            if not line:
                break
            event = json.loads(line)
            message = event.get('message', {})
            content += message.get('content', '')
            thinking_tokens += bool(message.get('thinking'))
            if message.get('content') or event.get('done') or event.get('error'):
                print(json.dumps({'seconds': round(time.perf_counter()-started, 3),
                                  'content': content, 'thinking_chunks': thinking_tokens,
                                  'metrics': {key: value for key, value in event.items() if key != 'message'}}), flush=True)
            if event.get('done'):
                return response.status == 200 and bool(content.strip()) and event.get('done_reason') != 'length'
            if time.perf_counter()-started > timeout:
                break
    except Exception as error:
        print(json.dumps({'inference_error': str(error), 'seconds': round(time.perf_counter()-started, 3)}), flush=True)
    finally:
        connection.close()
    return False


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--text-only', action='store_true')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--metadata-only', action='store_true')
    parser.add_argument('--no-think', action='store_true')
    parser.add_argument('--prefill', action='store_true')
    args = parser.parse_args()
    for endpoint in ['/api/version', '/api/tags', '/api/ps']:
        metadata(endpoint)
    if not args.metadata_only:
        success = inference(args.text_only, args.timeout, args.no_think, args.prefill)
        metadata('/api/ps')
        sys.exit(0 if success else 1)
