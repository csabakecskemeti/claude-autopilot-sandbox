# Network Notes - DGX Spark Connectivity

## Key Insight

**SSH tunneling is NOT needed** for connecting to DGX Spark machines. LM Studio with `--bind 0.0.0.0` works correctly when the network is functioning properly.

## mDNS Hostnames Work!

**UPDATE 2026-05-02:** mDNS hostnames (`.local`) DO work inside Docker containers on macOS.

```bash
# This works in .env-dgx2:
LLM_HOST=spark-7ceb.local
```

Earlier assumption that Docker can't resolve `.local` was incorrect. Use hostnames when possible - they're more stable than IPs if DHCP changes.

## DGX2 (spark-7ceb / 192.168.4.62)

Experienced intermittent connectivity issues (2026-05-02):
- Ping works but port 11234 shows "Connection refused"
- `ss -tlnp` shows LM Studio correctly bound to `0.0.0.0:11234`
- SSH also stopped working during the issue
- **Root cause**: Network issue on DGX2 side, not LM Studio configuration
- **Solution**: Restart DGX2 network or the machine itself

## Correct LM Studio Startup

```bash
lms server start -p 11234 --bind 0.0.0.0
lms load <model-name> --gpu max -y
```

## Troubleshooting Checklist

1. **Test from Mac host first** (not Docker):
   ```bash
   curl http://192.168.4.62:11234/v1/models
   ```

2. **If connection refused, check on DGX**:
   ```bash
   # Is server running?
   lms status

   # What's it bound to?
   ss -tlnp | grep 11234
   # Should show: 0.0.0.0:11234
   ```

3. **If bound correctly but still failing**:
   - It's a network issue, not LM Studio
   - Try restarting network: `sudo systemctl restart NetworkManager`
   - Or restart the DGX machine

4. **Don't do**:
   - Don't set up SSH tunnels (unnecessary complexity)
   - Don't modify firewall (ufw is inactive on DGX2)
   - Don't blame Docker networking if Mac host curl also fails

## Network Topology

- Mac: 192.168.6.x subnet
- DGX1: 192.168.7.x subnet
- DGX2: 192.168.4.x subnet (spark-7ceb.local)

Different subnets but routing works when network is healthy.
