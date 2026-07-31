#!/usr/bin/env python3
"""Cliente interactivo, sin dependencias externas, para llama-server."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_URL = os.environ.get("LLAMA_API_URL", "http://127.0.0.1:8080")
DEFAULT_MODEL = os.environ.get("LLAMA_MODEL", "Qwen3.6-35B-A3B")
DEFAULT_SYSTEM = os.environ.get(
    "LLAMA_SYSTEM_PROMPT",
    "Eres un asistente útil, preciso y directo. Responde en español salvo que se solicite otro idioma.",
)
DEFAULT_TIMEOUT = int(os.environ.get("LLAMA_CHAT_TIMEOUT", "3600"))


class Colors:
    def __init__(self) -> None:
        enabled = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
        self.blue = "\033[1;34m" if enabled else ""
        self.green = "\033[1;32m" if enabled else ""
        self.yellow = "\033[1;33m" if enabled else ""
        self.dim = "\033[2m" if enabled else ""
        self.reset = "\033[0m" if enabled else ""


C = Colors()


class LlamaChat:
    def __init__(
        self,
        base_url: str,
        model: str,
        api_key: str | None,
        system_prompt: str,
        timeout: int,
        stream: bool,
        show_reasoning: bool,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key = api_key
        self.system_prompt = system_prompt
        self.timeout = timeout
        self.stream = stream
        self.show_reasoning = show_reasoning
        self.messages: list[dict[str, str]] = []
        self.last_timings: dict[str, Any] = {}
        self.last_usage: dict[str, Any] = {}

    def headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    def check_health(self) -> None:
        request = urllib.request.Request(f"{self.base_url}/health", headers=self.headers())
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                if response.status != 200:
                    raise RuntimeError(f"/health respondió HTTP {response.status}")
        except urllib.error.HTTPError as error:
            if error.code == 503:
                raise RuntimeError("el modelo todavía se está cargando (/health respondió 503)") from error
            raise RuntimeError(f"/health respondió HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise RuntimeError(f"no fue posible conectar con {self.base_url}: {error.reason}") from error

    def payload(self) -> dict[str, Any]:
        messages = [{"role": "system", "content": self.system_prompt}, *self.messages]
        return {"model": self.model, "messages": messages, "stream": self.stream}

    def ask(self, prompt: str) -> str:
        started_at = time.monotonic()
        self.last_timings = {}
        self.last_usage = {}
        self.messages.append({"role": "user", "content": prompt})
        body = json.dumps(self.payload(), ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}/v1/chat/completions",
            data=body,
            headers=self.headers(),
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                if self.stream:
                    answer = self._read_stream(response)
                else:
                    answer = self._read_response(response)
        except (urllib.error.HTTPError, urllib.error.URLError) as error:
            self.messages.pop()
            raise RuntimeError(self._format_http_error(error)) from error
        except (KeyboardInterrupt, TimeoutError):
            self.messages.pop()
            raise

        if not answer:
            self.messages.pop()
            raise RuntimeError("el servidor terminó la respuesta sin devolver contenido")
        self.messages.append({"role": "assistant", "content": answer})
        self._print_performance(time.monotonic() - started_at)
        return answer

    def _read_stream(self, response: Any) -> str:
        content_parts: list[str] = []
        reasoning_started = False
        content_started = False

        for raw_line in response:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                event = json.loads(data)
            except json.JSONDecodeError:
                continue

            self._capture_performance(event)

            choices = event.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            reasoning = delta.get("reasoning_content") or ""
            content = delta.get("content") or ""

            if reasoning and self.show_reasoning:
                if not reasoning_started:
                    print(f"{C.dim}[razonamiento]{C.reset}")
                    reasoning_started = True
                print(f"{C.dim}{reasoning}{C.reset}", end="", flush=True)

            if content:
                if reasoning_started and not content_started:
                    print(f"\n{C.green}[respuesta]{C.reset}")
                print(content, end="", flush=True)
                content_started = True
                content_parts.append(content)

        print()
        return "".join(content_parts)

    def _read_response(self, response: Any) -> str:
        result = json.load(response)
        self._capture_performance(result)
        message = result["choices"][0]["message"]
        reasoning = message.get("reasoning_content") or ""
        if reasoning and self.show_reasoning:
            print(f"{C.dim}[razonamiento]\n{reasoning}{C.reset}")
            print(f"{C.green}[respuesta]{C.reset}")
        content = message.get("content") or ""
        print(content)
        return content

    def _capture_performance(self, result: dict[str, Any]) -> None:
        timings = result.get("timings")
        usage = result.get("usage")
        if isinstance(timings, dict):
            self.last_timings.update(timings)
        if isinstance(usage, dict):
            self.last_usage.update(usage)

    def _print_performance(self, elapsed: float) -> None:
        predicted_n = self.last_timings.get("predicted_n")
        predicted_tps = self.last_timings.get("predicted_per_second")
        predicted_ms = self.last_timings.get("predicted_ms")

        if predicted_n is None:
            predicted_n = self.last_usage.get("completion_tokens")
        if predicted_tps is None and predicted_n is not None and elapsed > 0:
            predicted_tps = float(predicted_n) / elapsed
            approximate = True
        else:
            approximate = False

        if predicted_tps is None:
            print(f"{C.dim}[rendimiento] El servidor no devolvió métricas de tokens.{C.reset}")
            return

        parts = [f"generación: {'≈' if approximate else ''}{float(predicted_tps):.2f} tok/s"]
        if predicted_n is not None:
            parts.append(f"{int(predicted_n)} tokens")
        if predicted_ms is not None:
            parts.append(f"{float(predicted_ms) / 1000:.2f} s")

        prompt_n = self.last_timings.get("prompt_n")
        prompt_tps = self.last_timings.get("prompt_per_second")
        if prompt_n is not None and prompt_tps is not None:
            parts.append(f"prompt: {float(prompt_tps):.2f} tok/s ({int(prompt_n)} tokens)")

        print(f"{C.dim}[rendimiento] {' · '.join(parts)}{C.reset}")

    @staticmethod
    def _format_http_error(error: urllib.error.HTTPError | urllib.error.URLError) -> str:
        if isinstance(error, urllib.error.URLError) and not isinstance(error, urllib.error.HTTPError):
            return f"no fue posible conectar con el servidor: {error.reason}"

        assert isinstance(error, urllib.error.HTTPError)
        detail = ""
        try:
            raw = error.read().decode("utf-8", errors="replace")
            parsed = json.loads(raw)
            api_error = parsed.get("error", parsed)
            detail = api_error.get("message", raw) if isinstance(api_error, dict) else raw
        except (json.JSONDecodeError, AttributeError):
            detail = getattr(error, "reason", "")
        return f"HTTP {error.code}: {detail}"

    def clear(self) -> None:
        self.messages.clear()

    def save(self, filename: str | None = None) -> Path:
        if filename:
            path = Path(filename).expanduser()
        else:
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            path = Path.home() / ".local" / "state" / "llama-chat" / f"chat-{stamp}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        document = {
            "model": self.model,
            "url": self.base_url,
            "system": self.system_prompt,
            "messages": self.messages,
        }
        path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        path.chmod(0o600)
        return path


def show_help() -> None:
    print(
        """Comandos:
  /help                 Muestra esta ayuda
  /clear                Borra el historial de la conversación
  /system TEXTO         Cambia el mensaje de sistema y borra el historial
  /multi                Permite escribir varias líneas; termina con una línea que contenga .
  /save [ARCHIVO]       Guarda la conversación como JSON
  /info                 Muestra servidor, modelo y cantidad de mensajes
  /quit                 Sale del cliente"""
    )


def read_multiline() -> str:
    print("Escribe el mensaje. Termina con una línea que contenga solamente un punto:")
    lines: list[str] = []
    while True:
        line = input()
        if line == ".":
            return "\n".join(lines).strip()
        lines.append(line)


def interactive(chat: LlamaChat) -> int:
    print(f"{C.blue}llama-chat{C.reset} conectado a {chat.base_url}")
    print(f"Modelo: {chat.model}. Escribe /help para ver comandos.\n")

    while True:
        try:
            prompt = input(f"{C.blue}Tú>{C.reset} ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nHasta luego.")
            return 0

        if not prompt:
            continue
        if prompt in {"/quit", "/exit", "/salir"}:
            print("Hasta luego.")
            return 0
        if prompt == "/help":
            show_help()
            continue
        if prompt == "/clear":
            chat.clear()
            print("Historial borrado.")
            continue
        if prompt.startswith("/system "):
            chat.system_prompt = prompt.removeprefix("/system ").strip()
            chat.clear()
            print("Mensaje de sistema actualizado; historial borrado.")
            continue
        if prompt == "/multi":
            try:
                prompt = read_multiline()
            except (EOFError, KeyboardInterrupt):
                print("\nEntrada cancelada.")
                continue
            if not prompt:
                continue
        elif prompt.startswith("/save"):
            filename = prompt.removeprefix("/save").strip() or None
            print(f"Conversación guardada en: {chat.save(filename)}")
            continue
        elif prompt == "/info":
            print(f"Servidor: {chat.base_url}")
            print(f"Modelo: {chat.model}")
            print(f"Mensajes conservados: {len(chat.messages)}")
            continue
        elif prompt.startswith("/"):
            print(f"Comando desconocido: {prompt}. Usa /help.")
            continue

        print(f"{C.green}IA>{C.reset} ", end="", flush=True)
        try:
            chat.ask(prompt)
        except KeyboardInterrupt:
            print("\nPetición cancelada.")
        except (RuntimeError, TimeoutError) as error:
            print(f"\n{C.yellow}Error: {error}{C.reset}", file=sys.stderr)
        print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Cliente interactivo para la API de llama-server")
    parser.add_argument("prompt", nargs="*", help="pregunta directa; si se omite, abre el chat interactivo")
    parser.add_argument("--url", default=DEFAULT_URL, help=f"URL base (predeterminado: {DEFAULT_URL})")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"alias del modelo (predeterminado: {DEFAULT_MODEL})")
    parser.add_argument("--api-key", default=os.environ.get("LLAMA_API_KEY"), help="API key; es preferible usar LLAMA_API_KEY")
    parser.add_argument("--system", default=DEFAULT_SYSTEM, help="mensaje de sistema")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="timeout por respuesta en segundos")
    parser.add_argument("--no-stream", action="store_true", help="espera la respuesta completa en vez de mostrarla por partes")
    parser.add_argument("--show-reasoning", action="store_true", help="muestra reasoning_content cuando el servidor lo devuelve")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    chat = LlamaChat(
        base_url=args.url,
        model=args.model,
        api_key=args.api_key,
        system_prompt=args.system,
        timeout=args.timeout,
        stream=not args.no_stream,
        show_reasoning=args.show_reasoning,
    )

    try:
        chat.check_health()
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    if args.prompt:
        print(f"{C.green}IA>{C.reset} ", end="", flush=True)
        try:
            chat.ask(" ".join(args.prompt))
        except (RuntimeError, TimeoutError, KeyboardInterrupt) as error:
            print(f"\nError: {error}", file=sys.stderr)
            return 1
        return 0
    return interactive(chat)


if __name__ == "__main__":
    raise SystemExit(main())
