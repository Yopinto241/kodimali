const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1, viewport-fit=cover"
    />
    <title>Kodimali Payment Return</title>
    <style>
      :root {
        color-scheme: light;
        --bg-top: #f7f3e8;
        --bg-bottom: #dfeee7;
        --card: rgba(255, 255, 255, 0.92);
        --text: #13231d;
        --muted: #5c6d66;
        --accent: #0f8a5f;
        --accent-dark: #0a6b48;
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 24px;
        font-family: Arial, Helvetica, sans-serif;
        background:
          radial-gradient(circle at top left, rgba(255, 255, 255, 0.72), transparent 36%),
          linear-gradient(160deg, var(--bg-top), var(--bg-bottom));
        color: var(--text);
      }

      .card {
        width: min(100%, 460px);
        padding: 28px 24px;
        border-radius: 24px;
        background: var(--card);
        box-shadow: 0 24px 80px rgba(19, 35, 29, 0.14);
      }

      .badge {
        width: 56px;
        height: 56px;
        display: grid;
        place-items: center;
        border-radius: 999px;
        background: rgba(15, 138, 95, 0.12);
        color: var(--accent);
        font-size: 28px;
        font-weight: 700;
      }

      h1 {
        margin: 18px 0 10px;
        font-size: 28px;
        line-height: 1.1;
      }

      p {
        margin: 0;
        line-height: 1.55;
        color: var(--muted);
        font-size: 16px;
      }

      .actions {
        display: grid;
        gap: 12px;
        margin-top: 24px;
      }

      button,
      a {
        appearance: none;
        border: 0;
        border-radius: 14px;
        padding: 14px 16px;
        text-align: center;
        font-size: 16px;
        font-weight: 700;
        text-decoration: none;
        cursor: pointer;
      }

      .primary {
        background: var(--accent);
        color: white;
      }

      .primary:hover {
        background: var(--accent-dark);
      }

      .secondary {
        background: rgba(15, 138, 95, 0.08);
        color: var(--accent-dark);
      }

      .note {
        margin-top: 18px;
        font-size: 14px;
      }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="badge">✓</div>
      <h1>Payment received</h1>
      <p>
        You can now return to the Kodimali app. If your payment is already
        confirmed, the agent phone number will appear automatically after you go
        back.
      </p>
      <div class="actions">
        <button class="primary" type="button" onclick="goBack()">
          Return to Kodimali App
        </button>
        <a class="secondary" href="/" rel="noreferrer">
          Reload this page
        </a>
      </div>
      <p class="note">
        If the app does not open by itself, close this browser page and go back
        to Kodimali manually.
      </p>
    </main>
    <script>
      function goBack() {
        if (window.history.length > 1) {
          window.history.back();
          return;
        }
        window.close();
      }
    </script>
  </body>
</html>`;

Deno.serve((_request) => {
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
});
