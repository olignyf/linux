#!/usr/bin/env bash
# gpu-diagnose.sh - Full GPU diagnostic script

echo "=== GPU Diagnostic Script ==="
echo

# 1. List PCI devices
echo "[1] PCI Devices (GPU-related):"
lspci -nnk | grep -A3 -E "VGA|3D|Display"
echo

# 2. Kernel modules
echo "[2] NVIDIA kernel modules loaded:"
lsmod | grep -E "nvidia|nouveau" || echo "No NVIDIA-related modules loaded"
echo

# 3. NVIDIA driver version
echo "[3] NVIDIA driver version:"
if [ -f /proc/driver/nvidia/version ]; then
    cat /proc/driver/nvidia/version
else
    echo "NVIDIA kernel driver not loaded"
fi
echo

# 4. dmesg logs (NVIDIA/GPU errors)
echo "[4] Kernel logs (NVRM/GPU related):"
if command -v sudo &>/dev/null; then
    sudo dmesg | grep -iE "nvrm|nvidia|gpu" | tail -n 20
else
    dmesg | grep -iE "nvrm|nvidia|gpu" | tail -n 20 || echo "No GPU-related logs found"
fi
echo

# 5. Secure Boot state
echo "[5] Secure Boot status:"
if command -v mokutil &>/dev/null; then
    mokutil --sb-state || echo "Could not determine (mokutil failed)"
else
    echo "mokutil not installed"
fi
echo

# 6. nvidia-smi check
echo "[6] nvidia-smi output:"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi || echo "nvidia-smi failed (no NVIDIA device found or driver issue)"
else
    echo "nvidia-smi not installed"
fi
echo

# 7. Installed NVIDIA packages (Debian/Ubuntu based)
echo "[7] Installed NVIDIA packages:"
if command -v apt &>/dev/null; then
    apt list --installed 2>/dev/null | grep -i nvidia | grep -vE "lang|firmware" || echo "No NVIDIA packages found via apt"
else
    echo "apt not found (skipping package check)"
fi
echo

# 8. Kernel driver binding
echo "[8] Kernel driver in use for each GPU:"
lspci -k | grep -A2 -E "VGA|3D|Display"
echo

# 9. Quick summary
echo "=== Summary ==="
if lspci | grep -i nvidia >/dev/null; then
    echo "✅ NVIDIA GPU detected at PCI level."
    if lsmod | grep -q nvidia; then
        echo "✅ NVIDIA driver module is loaded."
        if nvidia-smi &>/dev/null; then
            echo "✅ nvidia-smi reports GPU."
        else
            echo "⚠️ NVIDIA driver is loaded but nvidia-smi cannot see the GPU."
            echo "   → Possible causes: Secure Boot, driver-userland mismatch, GPU disabled in BIOS, or hardware issue."
        fi
    else
        echo "⚠️ NVIDIA GPU found but driver module not loaded."
    fi
else
    echo "❌ No NVIDIA GPU detected on PCI bus."
fi
echo
echo "Done."
