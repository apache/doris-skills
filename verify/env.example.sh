# Copy to env.sh (gitignored) and fill in. env.sh is sourced by run.sh.
# Connection uses the MySQL protocol — the always-available Doris path.

export DORIS_HOST="127.0.0.1"     # FE host
export DORIS_PORT="9030"          # FE MySQL query port (NOT the 8030/8080 HTTP port)
export DORIS_USER="root"
export DORIS_PASS=""              # leave empty if no password

# L2 (CLI-contract) only: doriscli also needs the FE HTTP port + a binary path.
export DORIS_HTTP_PORT=""         # FE HTTP port; empty => auto-detected via SHOW FRONTENDS (self-hosted 8030, cloud 8080)
export DORIS_CLI_PATH=""          # path to the doriscli binary; empty => auto-detect (sibling ../doris-cli/target/release, then PATH)

# Cluster identity — gates which version/mode-specific cases run.
export DORIS_MODE="integrated"    # "integrated" (self-hosted) | "cloud" (storage-compute)
export DORIS_VERSION=""           # e.g. "3.0.2"; empty => no version gating (all cases run, may falsely fail on clusters older than a case's min_version)

# Scratch database — created fresh each run, DROPped at the end.
# Must start with "doris_skill_verify" (runner refuses otherwise).
export SCRATCH_DB="doris_skill_verify"
