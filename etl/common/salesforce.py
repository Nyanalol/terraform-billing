"""Autenticacion a Salesforce por JWT bearer flow (sustituye al login con user/pass de Talend).

Talend conectaba con usuario+password+token en claro. Aqui usamos el flujo JWT del
Connected App: se firma un assertion con la clave privada (extraida del .jks a PEM) y se
canjea por un access_token. Sin secretos en codigo: todo entra por parametros/entorno.

Uso como modulo (test de conectividad):
    SF_CONSUMER_KEY=... SF_USERNAME=ops@g.softwareone.com \
    SF_PRIVATE_KEY_FILE=C:\\billing\\sf\\sf_jwt_key.pem \
    python -m etl.common.salesforce
"""
from __future__ import annotations

import os
import time

import jwt
import requests

PROD_AUDIENCE = "https://login.salesforce.com"
TEST_AUDIENCE = "https://test.salesforce.com"


def get_access_token(consumer_key: str, username: str, private_key_pem: str,
                     audience: str = PROD_AUDIENCE, timeout: int = 30) -> tuple[str, str]:
    """Devuelve (access_token, instance_url) via JWT bearer flow."""
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": consumer_key, "sub": username, "aud": audience, "exp": now + 300},
        private_key_pem,
        algorithm="RS256",
    )
    resp = requests.post(
        f"{audience}/services/oauth2/token",
        data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        timeout=timeout,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"JWT auth fallo ({resp.status_code}): {resp.text}")
    body = resp.json()
    return body["access_token"], body["instance_url"]


def connect(consumer_key: str, username: str, private_key_pem: str, audience: str = PROD_AUDIENCE):
    """Devuelve un cliente simple_salesforce.Salesforce autenticado por JWT."""
    from simple_salesforce import Salesforce

    token, instance_url = get_access_token(consumer_key, username, private_key_pem, audience)
    return Salesforce(instance_url=instance_url, session_id=token)


def connect_from_env():
    """Construye el cliente leyendo SF_CONSUMER_KEY / SF_USERNAME / SF_PRIVATE_KEY_FILE."""
    consumer_key = os.environ["SF_CONSUMER_KEY"]
    username = os.environ["SF_USERNAME"]
    key_file = os.environ["SF_PRIVATE_KEY_FILE"]
    audience = TEST_AUDIENCE if os.environ.get("SF_SANDBOX") else PROD_AUDIENCE
    with open(key_file, "r", encoding="utf-8") as fh:
        private_key_pem = fh.read()
    return connect(consumer_key, username, private_key_pem, audience)


if __name__ == "__main__":
    sf = connect_from_env()
    org = sf.query("SELECT Id, Name, OrganizationType, IsSandbox FROM Organization LIMIT 1")
    rec = org["records"][0]
    print("JWT OK ->", sf.sf_instance)
    print("  Org:", rec["Name"], "| type:", rec["OrganizationType"], "| sandbox:", rec["IsSandbox"])
