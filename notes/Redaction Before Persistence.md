---
id: 20260506222911
aliases: ["redaction", "secret filtering"]
tags: ["security", "logging"]
---
Histlog should redact common secrets before writing shell-derived data to persistent NDJSON files.

## What

All shell-derived strings are untrusted. Before persistence, histlog should detect common secret-like values, replace them with redacted markers, and record that redaction occurred.

## Why

Shell commands and environment-derived strings may contain tokens, keys, credentials, or prompt-injection text that later tools could consume. Redaction reduces accidental credential retention while keeping event structure useful.

## How

Apply redaction in the session writer and import path before NDJSON encoding. Do not shell-interpolate untrusted values; use structured command invocation such as `System.cmd/3` when external commands are required.

## Links

- [[Rich Command Metadata Collection]] - Metadata capture must be bounded by security controls.
- [[NDJSON Log Format]] - Stores redacted records after filtering.
- [[AI Agent Team Workflow]] - Includes security review as a recurring responsibility.
