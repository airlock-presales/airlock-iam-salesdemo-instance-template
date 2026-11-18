# Usage

## URLs

| | URL |
|-|-----|
| IAM Loginapp | `https://<fqdn>/auth-login/` (also `https://<fqdn>/`) |
| IAM Adminapp | `https://<fqdn>/auth-admin/`, `https://<fqdn>:8443/auth-admin/` (only from `vm_admin_ips`) |
| ArgoCD | `https://<fqdn>/argocd/` (IAM login, administrators only; also portal group *administration*) |
| Adminer | `https://<fqdn>/adminer/` (IAM login, administrators only; also portal group *administration*) |
| Headlamp | `https://<fqdn>/headlamp/` (IAM login, administrators only; also portal group *administration*) |
| Mailpit | `https://<fqdn>/mailpit/` (IAM login, administrators only; also portal group *administration*) |

## Command line access

Phase 2 writes the access configuration into the instance directory:
```
source output/env-setup      # sets KUBECONFIG and TALOSCONFIG
kubectl get pods -A
talosctl dashboard
```

Without local tools, use the debug container in the cluster (argocd, kubectl, k9s):
```
kubectl -n argocd exec -it deploy/argocd-cli -- k9s
kubectl -n argocd exec -it deploy/argocd-cli -- bash     # interactive shell: -it is required
kubectl -n argocd exec deploy/argocd-cli -- argocd app list
```
`argocd` in the debug container runs in core mode (`ARGOCD_OPTS=--core`): it uses the Kubernetes API with the container's service account - no login, independent of argocd-server and the IAM login.

Gateway address (LoadBalancer IP), for name resolution on local platforms:
```
kubectl -n airlock-gateway get svc
```

## Credentials

| | User | Password |
|-|------|----------|
| ArgoCD | IAM login (local administrators, Airlock 2FA or passkey); built-in `admin` (password login blocked by Microgateway) | setting `sec_password_argocd`; if empty: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| IAM Adminapp (emergency administrator) and Loginapp (realm administrator) | `emergency`, `admin` | setting `sec_password_iam` (initial password; changed passwords are kept) |
| Adminer | IAM login (local administrators, Airlock 2FA or passkey) | none - automatic login to database `iam` (user `iam`) |
| IAM database (MariaDB `iam-mariadb.iam.svc.cluster.local`, database `iam`) | `iam` | `kubectl -n iam get secret iam-db -o jsonpath='{.data.password}' \| base64 -d` |
| Headlamp | IAM login (local administrators, Airlock 2FA or passkey) | none - Headlamp uses its service account (`cluster-admin`) |
| Mailpit | IAM login (local administrators, Airlock 2FA or passkey) | none - Microgateway propagates the basic authentication (secret `mailpit-ui-auth`) |

## End-user login

Demo application: `https://<fqdn>/auth-login/` (also `https://<fqdn>/`).

- **Self-registration** ("Sign up" on the login page): username, email address (verified with a code), optional first and last name, then the email address of the responsible administrator, then the registration type:
  - **Easy**: password, then optionally a second factor (Airlock 2FA, OATH OTP, email OTP, or none).
  - **Identity check (KYC)**: identity proofing with the ID document via PXL Vision (test environment): a link (on a smartphone) or a QR code to scan; afterwards "continue" - if the check is not completed yet, IAM waits up to 20 seconds, then offers to go back to the QR code. First/last name, birthdate, document number and type are taken from the document, the user is marked as identity verified (`medusa_user.identity_verified`, `idp_doc_number`, `idp_doc_type`). Then password and optional second factor as above.

  Registration is controlled: new users stay locked until an administrator unlocks them in the Adminapp. The flow looks up the responsible administrator (user with the entered email address and role `partner-admin`) through the Adminapp REST API (Lua `ScriptableStep`, technical administrator `selfreg-lookup` in `medusa_admin`, roles `superadmin,demo-admin`, created by `init-db`; password from OpenTofu, reset at every IAM start). If found, the user gets the realm `users-<company>` (context data `company` of the administrator, normalized for the realm name: spaces become `-`, other characters than letters, digits, `-`, `_` become `_`, max. 44 characters; partner administrators manage it through the realm role `adm-<company>`; without company: `demo-users`) and the administrator an email; if not, the user gets realm `demo-users` and the marker role `registration-orphan` (may be deleted). Either way, the user sees the same message. The entered address is stored in `medusa_user.responsible_admin` (Adminapp user detail page).
- **Login with passkey**: passwordless on the login page, no second factor.
- **Login with password**: then the user selects one of the registered second factors (passkey, Airlock 2FA, OATH OTP, email OTP); with only one factor, it is used directly. Users without a second factor are offered to register one (passkey, Airlock 2FA, OATH OTP, email OTP) or to continue with password only.
- **Email OTP** is opt-in: available only once enabled by the user (registration or login), stored in `medusa_user.email_otp_enabled`.
- Emails (verification codes, OTPs) are caught by Mailpit unless an SMTP server is set.

Self-services (portal `https://<fqdn>/auth-login/ui/app/protected/portal`, after login):

| Self-service | Approval |
|---|---|
| change password | old password |
| change first/last name | Airlock 2FA or passkey, if registered; otherwise none |
| change email address | code sent to the new address |
| passkeys: register, rename, enable/disable | - |
| passkeys: remove | Airlock 2FA or passkey (required) |
| Airlock 2FA: activate new device, rename | - |
| Airlock 2FA: delete device | Airlock 2FA or passkey (required) |
| Airlock 2FA: recovery information (new phone, from backup - handled by Futurae, not by IAM) | - |
| OATH OTP: register (replaces an existing token) | - |
| email OTP: enable / disable | disable: Airlock 2FA or passkey (required) |
| Remember-Me devices | - |

Recovery:
- **Forgotten password** (link on the login page): user identification, code sent by email, approval with a registered second factor (Airlock 2FA, passkey, OATH OTP; none if the user has no such factor), new password.
- **Lost second factor** (button "recovery" on the login page): login with password and a code sent by email (independent of the email OTP opt-in), then the portal. In this session, removing passkeys and Airlock 2FA devices needs no approval; a new factor can be registered. OATH OTP: register again (replaces the lost token).
- **Helpdesk**: administrators remove a user's factors in the Adminapp.

## Administrator access

The Adminapp uses realm administration (delegation-based access control): administrators are users, each user belongs to one realm; realm roles and delegations define what they may do.

Created by the init container `init-db` at the first start (if missing), with the initial password from the setting `sec_password_iam` (stored in cleartext, hashed by IAM at the first login):

| | Store | Roles | Realm | Login |
|-|-------|-------|-------|-------|
| Emergency administrator `emergency` | `medusa_admin` | `superadmin,realmadmin,demo-admin` | - | none at the moment (see below) |
| Realm administrator `admin` | `medusa_user` | `demo-admin,superadmin` | `demo-admins` | Loginapp, then portal entry *Adminapp* |

**Local administrators** (users in `medusa_user` with role `superadmin` or `demo-admin`) open the Adminapp from the application portal (group *administration*, entry *Adminapp*, new tab). The target application `adminapp-local` requires Airlock 2FA or a passkey - skipped if already used at login; users without either factor have no access (register one in the portal first). The Adminapp receives an SSO ticket with the user's roles and realm. Unauthenticated requests to `https://<fqdn>/auth-admin/` are sent to the Loginapp (`/auth-login/ui/app/auth/application/access/adminapp-local`, Adminapp `customLoginUrl`).

**Emergency access**: not available at the moment (needs a product change). The Adminapp password login (`adminAuthenticator`) checks users in `medusa_user`, but `customLoginUrl` sends all logins to the Loginapp. The emergency administrator `emergency` stays in `medusa_admin` (also used by the Adminapp REST API basic authentication). Later restricted to a source-IP-protected path (e.g. port 8443).

**Mailpit** (`https://<fqdn>/mailpit/`, portal group *administration*, entry *Mailpit*): Microgateway is the OIDC relying party (client `mailpit`) of the IAM authorization server `demo` (issuer `https://<fqdn>/auth-login/rest/oauth2/authorization-servers/demo`). The target application `mailpit` requires a local administrator (role `superadmin` or `demo-admin`) with Airlock 2FA or a passkey (skipped if already used at login). The ID token carries the claim `mailpit_authorization` (`Basic base64(admin:<password>)`), which Microgateway forwards as `Authorization` header to Mailpit. OpenTofu creates the client secret, the Mailpit password and the ID token signing key (PKCS#12, secret `iam-credentials`). The authorization server `demo` is meant for further tools.

**ArgoCD** (`https://<fqdn>/argocd/`, portal entry *ArgoCD*): all of `/argocd/` is behind Microgateway (OIDC relying party, client `argocd-gw`). Single sign-on: Microgateway exchanges the access token of its OIDC session at IAM (token exchange, audience `argocd`, claim `argocd_user: admin`, `sub` = IAM username, 10 minutes; cached in the Microgateway session, exchanged again when expired) and forwards the result as bearer token; ArgoCD validates it as a token of its OIDC issuer. ArgoCD's own login with IAM (OIDC client `argocd`, `oidc.config` in `argocd-cm`) remains as fallback. The authorization server `demo` issues JWT access tokens (subject tokens of the exchange; their signature is not checked by IAM, the exchange requires the client secret of `argocd-gw`). Both use the same flow as Mailpit (`authFlow-adminTools`). The ID token carries the static claim `argocd_user: admin`, mapped to `role:admin` (ArgoCD RBAC; the IAM username stays in `sub`). ArgoCD reaches IAM through Microgateway: the gateway has a fixed LoadBalancer address (first of the pool, PureLB annotation), ArgoCD resolves the FQDN to it (`hostAliases`); with `tls_issuer = internal`, ArgoCD skips the certificate check. Microgateway blocks the password login of the built-in `admin` (`POST /argocd/api/v1/session`, AccessControlPolicy `argocd`); `argocd-cli` (`argocd --core`) is not affected.

**Headlamp** (`https://<fqdn>/headlamp/`, portal entry *Headlamp*): behind Microgateway (OIDC relying party, client `headlamp`, flow `authFlow-adminTools`). Headlamp has no login of its own (`unsafeUseServiceAccountToken`): every user acts as Headlamp's service account (`cluster-admin`); the Kubernetes audit log shows the service account, not the user.

**Adminer** (`https://<fqdn>/adminer/`, portal entry *Adminer*): behind Microgateway (OIDC relying party, client `adminer`, flow `authFlow-adminTools`). Automatic login to database `iam` with the IAM database account (secret `adminer-db`): plugin [login-auth-proxy](https://github.com/omattsson/adminer-login-auth-proxy) (vendored, commit `efbef4c`), Microgateway sends the IAM username in a header with an unguessable name (`X-Auth-User-<random>`, OpenTofu, project settings `tools.adminer.auth_header`) - a client bypassing the gateway (e.g. a pod in the cluster) doesn't know the header name. Adminer's logout logs in again; log out with `https://<fqdn>/adminer/_oidc/logout`.

**Session lifetimes**: Microgateway sessions 4h (SessionHandling `sessionagent`, idle timeout 10m), IAM Loginapp session 4h (`sessionLifetime`), refresh tokens of the authorization server `demo` 4h1m.

`init-db` also creates the realm role `demo-admin` and its delegations for the realms `demo-admins` and `demo-users` (user, token and password management). Self-registered users are assigned to the realm `users-<company>` of their responsible administrator, else `demo-users` (`RealmAssignmentStep` in the self-registration flow) - users without a realm are not visible to any administrator. Users registered before this change: set the realm manually, e.g. with Adminer: `UPDATE medusa_user SET realm='demo-users' WHERE realm IS NULL;` Port 8443 (`https://<fqdn>:8443/auth-admin/`) leads to the same Adminapp, only from `vm_admin_ips` (Microgateway access control policy; on Azure also the network security group; no restriction if `vm_admin_ips` is empty).

**Partner administrators** (responsible administrators for self-registered users): users with role `partner-admin` and an email address, created by an administrator in the Adminapp; they see the Adminapp and Mailpit in the portal (not ArgoCD, Headlamp, Adminer). A registration of partner administrators through an external OIDC provider (e.g. secure.ergon.ch, account linking) is not part of the configuration template; the optional setting `airlock_iam_admin_oidc` provides client ID (`DEMO_ADMIN_OIDC_CLIENT_ID`) and secret (`[FILE]/run/secrets/iam/admin-oidc-client-secret`) for it, the Loginapp URL for the redirect URI is in `DEMO_LOGINAPP_URL`.

## IAM configuration

The IAM configuration belongs to the instance: `iam/iam-config.yaml` in the instance repository. `make init` creates the files of `iam/` (configuration, server-side texts) from the template of the base repository (`iam/`) if they don't exist; afterwards they are never overwritten - a newer template of a later release has to be merged manually (e.g. `diff -r salesdemo/iam iam`).

`make apply-3` deploys it: OpenTofu replaces the placeholder `@@FQDN@@` (redirect URIs of the OIDC clients - string lists can't use environment variables) and stores it in the configmap `iam/iam-config`; its hash is a pod annotation of IAM, so IAM restarts when the configuration changed. At IAM start, the init container `init-config` copies it into the instance, depending on the setting `airlock_iam_config_sync`:

- `changed` (default): only if the deployed configuration changed since the last copy. Changes made in the Config Editor survive restarts until the deployed configuration changes.
- `always`: on every start.
- `never`: never; use while working in the Config Editor.

A replaced configuration is kept in the instance directory as `iam-config.yaml.<timestamp>` (the 2 newest; IAM itself keeps the 20 newest activated configurations per application in `.activated-configs/`).

**Config Editor after a deployment:** activating in the Config Editor writes the whole configuration it shows. If it still shows the state from before a `make apply-3` (e.g. an open Config Editor, whose state survives IAM restarts in the session), activating overwrites the deployed configuration with the old one. Reload the Config Editor after a deployment before activating anything. To keep changes made in the Config Editor:
```
make iam-config-pull     # active configuration from IAM to iam/iam-config.yaml, FQDN replaced by @@FQDN@@
git diff iam/            # review
git commit -m "IAM configuration" iam/
make apply-3             # optional: the active configuration is the same, IAM restarts once
```

Server-side texts (e.g. email templates, messages of the flows): `iam/<app>-texts/strings_<language>.properties` in the instance repository (e.g. `loginapp-texts`, `adminapp-texts`; Java properties, `key = value`). `make apply-3` deploys them with the configuration (configmap `iam-config`, IAM restarts on a change); `init-config` copies them into the instance (`<instance>/<app>-texts/`) at every start, independent of `airlock_iam_config_sync`, and removes files it copied earlier that are no longer in the repository.

The configuration relies on the deployment (keep it when changing the configuration):
- secrets mounted as files: `/run/secrets/iam/` (secret `iam-credentials`: credentials of external services, OIDC client secrets, keys), `/run/secrets/iam-db/`,
- environment variables `DEMO_*` (statefulset `iam`), e.g. `DEMO_FQDN`, `DEMO_OIDC_ISSUER`, `DEMO_FUTURAE_SERVICE_ID`,
- OIDC clients of the tools (`mailpit`, `argocd`, `argocd-gw`, `headlamp`, `adminer`) and their redirect URIs, matching the Microgateway configuration,
- the state repository Valkey (`valkey.iam.svc.cluster.local`).

State repository (sessions, flow state) of Loginapp and Adminapp: Valkey in namespace `iam` (`SingleModeRedisStateRepository`, Redis namespace `iam`, no state encryption - Valkey is only reachable inside the cluster). Without persistence: IAM sessions survive IAM restarts (e.g. configuration changes), not Valkey restarts. Password: secret `iam-valkey`, created by OpenTofu.

Credentials for external services (e.g. SMTP) are instance settings; OpenTofu stores them in the secret `iam-credentials`, mounted to `/run/secrets/iam/`. The configuration references them with `[FILE]/run/secrets/iam/<key>`, other values with environment variables (`DEMO_*`).

## Certificate of the internal CA

With `tls_issuer = "provided"`, the gateway uses the certificate and key from the settings (`tls_certificate`, `tls_private_key`): OpenTofu creates the secret `airlock-gateway/gateway-tls-cert`, cert-manager is not involved. Renewal: new certificate and key in the settings, `make apply-3`. Switching an existing instance from `internal`/`letsencrypt` to `provided`: 1. `make apply-3` (updates the project settings; creating the secret fails, cert-manager's secret still exists), 2. wait until ArgoCD has removed the cert-manager Certificate (`kubectl -n airlock-gateway get certificate` empty), 3. `kubectl -n airlock-gateway delete secret gateway-tls-cert`, 4. `make apply-3` again. ArgoCD's login with IAM skips the certificate check for all issuers except `letsencrypt` (a provided certificate may come from a CA unknown to ArgoCD).

With `tls_issuer = "internal"`, browsers warn about the gateway certificate - and refuse passkeys (WebAuthn) on such a site, even after accepting the warning. To trust it, import the cluster CA:
```
kubectl -n cert-manager get secret cluster-ca-key-pair -o jsonpath='{.data.ca\.crt}' | base64 -d > salesdemo-ca.crt
```

## Troubleshooting

- **Applications**: ArgoCD UI, or `argocd app list` in the debug container. Applications are deployed in sync waves; an unhealthy application blocks the following waves.
- **Changed settings** (`sops edit`, `make apply-3`) are picked up by ArgoCD at the next manifest refresh; to apply them immediately, use *Hard Refresh* on the application in the ArgoCD UI.
- **IAM logs**: structured logs on stdout (`kubectl -n iam logs iam-0`), traditional log files on the volume `iam-logs` (7 days):
  ```
  kubectl -n iam exec iam-0 -- ls /home/airlock/iam/instances/auth/logs
  ```
- **IAM start-up**: init containers `init-instance`, `init-config` and `init-db` prepare the instance, its configuration and the database schema; check their logs with e.g. `kubectl -n iam logs iam-0 -c init-config`.
- **Talos**: `talosctl dmesg`, `talosctl logs kubelet`, `talosctl get disks`.
