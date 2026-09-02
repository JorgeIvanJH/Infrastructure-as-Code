#!/usr/bin/env python3
"""Expose refreshable AWS CLI login credentials to one local SDK process."""

import argparse
import json
import os
import shutil
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def find_aws_cli() -> str:
    executable = shutil.which("aws")
    if executable:
        return executable

    all_users_path = r"C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    if os.path.isfile(all_users_path):
        return all_users_path

    raise FileNotFoundError("AWS CLI was not found")


def make_handler(profile: str, authorization_token: str):
    class CredentialHandler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
            if self.path != "/credentials":
                self.send_error(404)
                return

            if self.headers.get("Authorization") != authorization_token:
                self.send_error(401)
                return

            try:
                completed = subprocess.run(
                    [
                        find_aws_cli(),
                        "configure",
                        "export-credentials",
                        "--profile",
                        profile,
                        "--format",
                        "process",
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                exported = json.loads(completed.stdout)
                response = {
                    "AccessKeyId": exported["AccessKeyId"],
                    "SecretAccessKey": exported["SecretAccessKey"],
                    "Token": exported["SessionToken"],
                    "Expiration": exported["Expiration"],
                }
                payload = json.dumps(response).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception as error:  # Return a useful SDK error without secrets.
                payload = json.dumps(
                    {"Code": "CredentialRefreshError", "Message": str(error)}
                ).encode("utf-8")
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        def log_message(self, _format, *_args):
            return

    return CredentialHandler


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--profile", default="default")
    parser.add_argument("--token", required=True)
    arguments = parser.parse_args()

    handler = make_handler(arguments.profile, arguments.token)
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
