#!/usr/bin/env bash
#
# Runs INSIDE the crave devspace, invoked by the `wake` job of
# .github/workflows/crdroid-onyx.yml as:
#
#   crave devspace -- "curl -fsSL .../scripts/ensure-runner.sh | bash"
#
# Makes sure the GitHub Actions self-hosted runner is listening, so a
# hibernated devspace cannot leave a self-hosted job queued forever. Touches
# nothing but ~/actions-runner: no repo, no make, no ROM source. The devspace
# rules (https://github.com/FOSSonTop/crave/blob/master/rules.md) forbid
# syncing or building here.
#
set -euo pipefail

SESSION=ghactions   # the name force-restart-runner.yml also expects
RUNNER="$HOME/actions-runner/run.sh"

cd "$HOME"

if [ ! -x "$RUNNER" ]; then
    echo "FATAL: $RUNNER is missing. Run configure-runner.yml first." >&2
    exit 1
fi

# Conservative on purpose: a false "already up" just makes the job queue and
# time out visibly, whereas a false "down" would kill a build in progress.
# FORCE=1 (used by force-restart-runner.yml) skips the check and restarts.
if [ "${FORCE:-0}" != "1" ] \
   && tmux has-session -t "$SESSION" 2>/dev/null \
   && pgrep -f 'Runner.Listener|actions-runner/run.sh' >/dev/null 2>&1; then
    echo "runner already listening"
    exit 0
fi

echo "(re)starting the runner"
tmux kill-session -t "$SESSION" 2>/dev/null || true

# -c "$HOME" matters: this devspace's .bashrc cds to /crave-devspaces, so a
# plain `tmux new-session -d` starts the pane there and the relative
# ./actions-runner/run.sh misses. Same reason for the explicit cd below.
tmux new-session -d -s "$SESSION" -c "$HOME"
tmux send-keys -t "$SESSION" 'cd "$HOME" && exec ./actions-runner/run.sh' Enter

for i in $(seq 1 30); do
    if pgrep -f 'Runner.Listener' >/dev/null 2>&1; then
        echo "runner up after ${i}s"
        tmux capture-pane -p -t "$SESSION" | grep -v '^$' | tail -5
        exit 0
    fi
    sleep 1
done

echo "FATAL: the runner did not come up within 30s" >&2
tmux capture-pane -p -t "$SESSION" | grep -v '^$' | tail -20 >&2
exit 1
