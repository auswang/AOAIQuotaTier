import os
from flask import Flask, render_template

app = Flask(__name__)


@app.route("/")
def index():
    return render_template(
        "index.html",
        client_id=os.environ.get("AZURE_CLIENT_ID", ""),
        tenant_id=os.environ.get("AZURE_TENANT_ID", "common"),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)), debug=True)
