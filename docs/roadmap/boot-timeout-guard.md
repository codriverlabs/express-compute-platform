# Boot Timeout Guard

## Problem

If the boot hangs silently (e.g. `kubectl wait` blocking forever, helm stuck)
the `fail` ERR trap in `progress.sh` never fires — DynamoDB stays at the last
written state and the SSE stream blocks until the Lambda's 15-minute limit.

## Proposed fix

Add a background timeout subshell in `workstation-boot.sh` after the IMDS wait:

```bash
MAIN_PID=$$
( sleep 1500 \
    && update_progress "failed" "Boot timeout after 25min" 0 \
    && kill -TERM -$MAIN_PID 2>/dev/null ) &
TIMEOUT_PID=$!
```

Cancel it on successful completion:

```bash
kill $TIMEOUT_PID 2>/dev/null || true
```

25 minutes gives headroom over the 3-minute boot target while terminating
before the SSE Lambda's 15-minute max. On timeout, systemd also marks
`eks-dx-boot.service` as failed.
