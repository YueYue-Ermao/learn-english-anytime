# Language Learning Service

This small service keeps the model API key out of the macOS application. It provides contextual translation/expression generation and explicit grammar Q&A.

Endpoints:

- `POST /v1/translations/contextual`
- `POST /v1/grammar/questions`
- `GET /healthz`

## Local mock mode

```bash
CONTEXT_TRANSLATION_MOCK=1 python3 server.py
```

In the app, open **AI 服务设置**, choose **使用本机开发服务**, and save. Mock mode verifies both optional AI flows but does not provide production-quality translation or grammar tutoring.

## Real model mode

```bash
OPENAI_API_KEY="your-server-side-key" \
OPENAI_MODEL="gpt-6-astra" \
python3 server.py
```

The model can be changed through `OPENAI_MODEL`. Production deployment must add TLS, authentication, per-user rate limits, cost limits, secret management, and redacted monitoring. Do not expose this development server directly to the internet.

The server uses the OpenAI Responses API and Structured Outputs. It sets `store: false`, does not persist request bodies, and does not send application IDs, URLs, document titles, or full documents. Grammar requests contain only the sentence, the user's question, and an optional scenario explicitly entered by the user.

Official references:

- https://developers.openai.com/api/docs/guides/text
- https://developers.openai.com/api/docs/guides/structured-outputs
