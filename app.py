import os
from datetime import datetime, timezone, timedelta
from flask import Flask, render_template

app = Flask(__name__)

# Build time in Beijing time (UTC+8), captured at startup
_beijing_tz = timezone(timedelta(hours=8))
BUILD_TIME = datetime.now(_beijing_tz).strftime("%Y-%m-%d %H:%M:%S")


@app.route("/")
def index():
    return render_template(
        "index.html",
        client_id=os.environ.get("AZURE_CLIENT_ID", ""),
        tenant_id=os.environ.get("AZURE_TENANT_ID", "common"),
        austin_tenant=os.environ.get("AUSTIN_TENANT", ""),
        build_time=BUILD_TIME,
    )


@app.route("/health")
def health():
    return "OK", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)), debug=False)
