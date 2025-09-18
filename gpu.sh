#!/usr/bin/env bash
# gpu-diagnose.sh - Full GPU diagnostic script

# Check for command line arguments
if [ "$1" = "--remove-nvidia" ]; then
    echo "=== NVIDIA Driver Removal ==="
    echo "This will completely remove all NVIDIA drivers and packages."
    echo "⚠️  WARNING: This will break NVIDIA GPU functionality until drivers are reinstalled."
    echo
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing all NVIDIA packages..."
        
        # Check if running as root - require explicit sudo invocation
        if [ "$EUID" -eq 0 ]; then
            REMOVE_CMD=""
        else
            echo "❌ Error: This script must be run as root for the --remove-nvidia option"
            echo "   Please run: sudo $0 --remove-nvidia"
            echo "   The --remove-nvidia option requires root privileges for safety"
            exit 1
        fi
        
        # Stop any processes using NVIDIA devices
        echo "Stopping processes using NVIDIA devices..."
        $REMOVE_CMD lsof /dev/nvidia* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u | xargs -r $REMOVE_CMD kill -9 2>/dev/null || true
        
        # Remove all NVIDIA packages
        echo "Removing NVIDIA packages..."
        $REMOVE_CMD apt remove --purge '^nvidia-.*' -y
        
        # Clean up any remaining packages
        echo "Cleaning up remaining packages..."
        $REMOVE_CMD apt autoremove -y
        
        # Remove any remaining NVIDIA modules
        echo "Unloading NVIDIA kernel modules..."
        $REMOVE_CMD rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
        
        # Remove NVIDIA configuration files
        echo "Removing NVIDIA configuration files..."
        $REMOVE_CMD rm -rf /etc/nvidia* /etc/modprobe.d/nvidia* /etc/X11/xorg.conf.d/*nvidia* 2>/dev/null || true
        
        # Check if NVIDIA was installed via official installer (not package manager)
        if [ -f /usr/bin/nvidia-uninstall ] && ! dpkg -S /usr/bin/nvidia-uninstall &>/dev/null; then
            echo "Detected NVIDIA drivers installed via official installer (not package manager)"
            echo "Using NVIDIA's official uninstaller..."
            $REMOVE_CMD /usr/bin/nvidia-uninstall --no-questions --silent
        else
            # Remove nvidia-smi binary if it exists and is not managed by package system
            if [ -f /usr/bin/nvidia-smi ] && ! dpkg -S /usr/bin/nvidia-smi &>/dev/null; then
                echo "Removing unmanaged nvidia-smi binary..."
                $REMOVE_CMD rm -f /usr/bin/nvidia-smi
            fi
            
            # Remove any other NVIDIA binaries that might not be managed by packages
            echo "Removing any remaining NVIDIA binaries..."
            $REMOVE_CMD find /usr/bin -name "*nvidia*" -type f -executable -not -path "*/nvidia-settings*" -delete 2>/dev/null || true
        fi
        
        echo
        echo "✅ NVIDIA drivers completely removed!"
        echo "⚠️  IMPORTANT: Reboot your system to complete the cleanup."
        echo "   After reboot, you can install fresh NVIDIA drivers."
        echo
        read -p "Do you want to reboot now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Rebooting in 5 seconds... (Press Ctrl+C to cancel)"
            sleep 5
            $REMOVE_CMD reboot
        else
            echo "Please reboot manually when convenient."
        fi
        exit 0
    else
        echo "NVIDIA driver removal cancelled."
        exit 0
    fi
fi

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

# 9. Check for specific error conditions
echo "[9] Checking for specific driver compatibility issues:"
OPEN_KERNEL_REQUIRED=false
VERSION_MISMATCH=false

if dmesg | grep -q "requires use of the NVIDIA open kernel modules"; then
    echo "⚠️  DETECTED: GPU requires NVIDIA open kernel modules"
    echo "   → Your GPU needs the open kernel driver instead of proprietary driver"
    OPEN_KERNEL_REQUIRED=true
fi

# Check for driver/library version mismatch
if nvidia-smi 2>&1 | grep -q "Driver/library version mismatch"; then
    echo "⚠️  DETECTED: Driver/library version mismatch"
    echo "   → NVIDIA kernel driver and userland libraries are incompatible"
    VERSION_MISMATCH=true
    
    # Check if nvidia-smi binary version matches driver version
    KERNEL_VERSION=$(cat /proc/driver/nvidia/version 2>/dev/null | grep -o '580\.[0-9]\+\.[0-9]\+' | head -1)
    SMI_VERSION=$(strings /usr/bin/nvidia-smi 2>/dev/null | grep -E '^580\.[0-9]+\.[0-9]+$' | head -1)
    
    if [ -n "$KERNEL_VERSION" ] && [ -n "$SMI_VERSION" ] && [ "$KERNEL_VERSION" != "$SMI_VERSION" ]; then
        echo "   → CAUSE: nvidia-smi binary version ($SMI_VERSION) doesn't match kernel driver ($KERNEL_VERSION)"
        SMI_VERSION_MISMATCH=true
    else
        SMI_VERSION_MISMATCH=false
    fi
    
    # Check if processes are using NVIDIA devices
    NVIDIA_PROCESSES=$(sudo lsof /dev/nvidia* 2>/dev/null | grep -v "COMMAND" | wc -l)
    if [ "$NVIDIA_PROCESSES" -gt 0 ]; then
        echo "   → WARNING: $NVIDIA_PROCESSES process(es) are using NVIDIA devices"
        echo "   → These processes must be stopped before fixing the version mismatch"
        PROCESSES_USING_GPU=true
    else
        PROCESSES_USING_GPU=false
    fi
fi

# 10. Quick summary
echo "=== Summary ==="
if lspci | grep -i nvidia >/dev/null; then
    echo "✅ NVIDIA GPU detected at PCI level."
    if lsmod | grep -q nvidia; then
        echo "✅ NVIDIA driver module is loaded."
        if nvidia-smi &>/dev/null; then
            echo "✅ nvidia-smi reports GPU."
        else
            echo "⚠️ NVIDIA driver is loaded but nvidia-smi cannot see the GPU."
            if [ "$OPEN_KERNEL_REQUIRED" = true ]; then
                echo "   → CAUSE: GPU requires NVIDIA open kernel modules (not proprietary driver)"
            elif [ "$VERSION_MISMATCH" = true ]; then
                echo "   → CAUSE: Driver/library version mismatch - kernel driver and userland libraries are incompatible"
            else
                echo "   → Possible causes: Secure Boot, driver-userland mismatch, GPU disabled in BIOS, or hardware issue."
            fi
        fi
    else
        echo "⚠️ NVIDIA GPU found but driver module not loaded."
    fi
else
    echo "❌ No NVIDIA GPU detected on PCI bus."
fi

# 11. Version mismatch fix prompt
if [ "$VERSION_MISMATCH" = true ] && [ "$OPEN_KERNEL_REQUIRED" = false ]; then
    echo
    echo "=== Driver Version Mismatch Fix ==="
    echo "Your NVIDIA kernel driver and userland libraries have version mismatches."
    echo "This typically happens after driver updates or mixed installations."
    
    if [ "$PROCESSES_USING_GPU" = true ]; then
        echo
        echo "⚠️  PROCESSES DETECTED: Some processes are currently using the GPU."
        echo "   → These must be stopped before fixing the version mismatch"
        echo "   → Current processes using GPU:"
        sudo lsof /dev/nvidia* 2>/dev/null | grep -v "COMMAND" | awk '{print "     " $1 " (PID: " $2 ")"}' | sort -u
        echo
        read -p "Do you want to stop these processes and fix the version mismatch? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Stopping processes using GPU..."
            # Kill processes using NVIDIA devices
            sudo lsof /dev/nvidia* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u | xargs -r sudo kill -9
            sleep 2
            echo "Processes stopped."
        else
            echo "Skipping version mismatch fix due to running processes."
            echo "To fix manually later:"
            echo "  1. Stop processes using GPU: sudo lsof /dev/nvidia*"
            echo "  2. Kill them: sudo kill -9 <PID>"
            echo "  3. Reinstall driver: sudo apt install --reinstall nvidia-driver"
            echo "  4. Reboot: sudo reboot"
            exit 0
        fi
    else
        echo
        read -p "Do you want to fix the version mismatch? (y/N): " -n 1 -r
        echo
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [ "$PROCESSES_USING_GPU" = false ]; then
        echo "Fixing driver version mismatch..."
        
        # Check if running as root or if sudo is available and working
        if [ "$EUID" -eq 0 ]; then
            FIX_CMD=""
        elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            FIX_CMD="sudo"
        else
            echo "❌ Error: Need root privileges or working sudo to fix version mismatch"
            echo "   Please run: sudo $0"
            echo "   Or ensure your user has sudo privileges"
            exit 1
        fi
        
        if [ "$SMI_VERSION_MISMATCH" = true ]; then
            echo "⚠️  nvidia-smi binary version mismatch detected!"
            echo "   nvidia-smi binary: $(strings /usr/bin/nvidia-smi 2>/dev/null | grep -E '^580\.[0-9]+\.[0-9]+$' | head -1)"
            echo "   kernel driver: $(cat /proc/driver/nvidia/version 2>/dev/null | grep -o '580\.[0-9]\+\.[0-9]\+' | head -1)"
            echo
            echo "This is a common issue with mixed NVIDIA driver installations."
            echo "The nvidia-smi binary was compiled for a different driver version."
            echo
            echo "Recommended solutions:"
            echo "1. Reinstall the entire NVIDIA driver stack:"
            echo "   sudo apt remove --purge '^nvidia-.*'"
            echo "   sudo apt autoremove"
            echo "   sudo apt install nvidia-driver"
            echo "   sudo reboot"
            echo
            echo "2. Or try to find a matching nvidia-smi binary:"
            echo "   sudo apt search nvidia-smi"
            echo
            echo "3. Use alternative GPU monitoring tools:"
            echo "   - lspci -k | grep -A2 -E 'VGA|3D|Display'"
            echo "   - cat /proc/driver/nvidia/version"
            echo "   - lsmod | grep nvidia"
            echo
            echo "⚠️  Manual intervention required - the script cannot automatically fix this."
        else
            echo "Attempting to reload NVIDIA modules without reboot..."
            # Try to unload and reload modules first
            echo "Unloading NVIDIA modules..."
            sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
            sleep 2
            echo "Reloading NVIDIA modules..."
            sudo modprobe nvidia nvidia_modeset nvidia_drm nvidia_uvm
            
            # Test if nvidia-smi works now
            if nvidia-smi &>/dev/null; then
                echo "✅ Version mismatch fixed by reloading modules!"
                echo "nvidia-smi is now working correctly."
            else
                echo "Module reload didn't fix the issue. Reinstalling driver..."
                $FIX_CMD apt update -y
                $FIX_CMD apt install --reinstall nvidia-driver -y
                
                if [ $? -eq 0 ]; then
                    echo "✅ Driver reinstallation complete!"
                    echo "⚠️  IMPORTANT: You must reboot your system for the changes to take effect."
                    echo "   After reboot, run this script again to verify the GPU is working."
                    echo
                    read -p "Do you want to reboot now? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo "Rebooting in 5 seconds... (Press Ctrl+C to cancel)"
                        sleep 5
                        reboot
                    else
                        echo "Please reboot manually when convenient."
                    fi
                else
                    echo "❌ Driver reinstallation failed. Manual intervention required."
                    echo "Try running: sudo apt install --reinstall nvidia-driver"
                fi
            fi
        fi
    else
        echo "Skipping version mismatch fix."
        echo "To fix manually later, run:"
        echo "  sudo apt update"
        echo "  sudo apt install --reinstall nvidia-driver"
        echo "  sudo reboot"
    fi
fi

# 12. Driver installation prompt
if [ "$OPEN_KERNEL_REQUIRED" = true ]; then
    echo
    echo "=== Driver Installation Required ==="
    echo "Your NVIDIA GPU requires the open kernel modules instead of the proprietary driver."
    echo "This will install nvidia-kernel-open-dkms and remove the current proprietary kernel module."
    
    # Pre-check for version conflicts
    CURRENT_VERSION=$(cat /proc/driver/nvidia/version 2>/dev/null | grep -o '580\.[0-9]\+\.[0-9]\+' | head -1)
    OPEN_VERSION="580.82.07"
    
    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$OPEN_VERSION" ]; then
        echo
        echo "⚠️  VERSION CONFLICT DETECTED:"
        echo "   Current proprietary driver: $CURRENT_VERSION"
        echo "   Available open driver: $OPEN_VERSION"
        echo "   → Installation will use --force-yes to override the newer version"
        echo
    fi
    echo
    read -p "Do you want to install the proper open kernel driver? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing NVIDIA open kernel modules..."
        
        # Check if running as root or if sudo is available and working
        if [ "$EUID" -eq 0 ]; then
            INSTALL_CMD="apt"
        elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            INSTALL_CMD="sudo apt"
        else
            echo "❌ Error: Need root privileges or working sudo to install packages"
            echo "   Please run: sudo $0"
            echo "   Or ensure your user has sudo privileges"
            exit 1
        fi
        
        # Install open kernel modules
        echo "Updating package list..."
        $INSTALL_CMD update -y
        
        # Check if we need to force installation due to version conflicts
        CURRENT_VERSION=$(cat /proc/driver/nvidia/version 2>/dev/null | grep -o '580\.[0-9]\+\.[0-9]\+' | head -1)
        OPEN_VERSION="580.82.07"
        
        echo "Installing nvidia-kernel-open-dkms..."
        if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$OPEN_VERSION" ]; then
            echo "⚠️  Detected version conflict: Current=$CURRENT_VERSION, Open=$OPEN_VERSION"
            echo "   → Will force installation to override newer proprietary modules"
            $INSTALL_CMD install -y nvidia-kernel-open-dkms
            # Force DKMS to override version conflicts
            dkms install nvidia/580.82.07 --force
        else
            $INSTALL_CMD install -y nvidia-kernel-open-dkms
        fi
        
        # Check if installation actually succeeded
        if [ $? -ne 0 ]; then
            echo "❌ Installation failed! Trying with DKMS force flag..."
            dkms install nvidia/580.82.07 --force
            if [ $? -ne 0 ]; then
                echo "❌ Installation still failed. Manual intervention required."
                echo "Try running: sudo apt install nvidia-kernel-open-dkms"
                echo "Then: sudo dkms install nvidia/580.82.07 --force"
                echo "Finally: sudo apt remove nvidia-kernel-dkms"
                exit 1
            fi
        fi
        
        echo "Removing proprietary kernel module..."
        $INSTALL_CMD remove -y nvidia-kernel-dkms
        
        echo
        echo "✅ Installation complete!"
        echo "⚠️  IMPORTANT: You must reboot your system for the changes to take effect."
        echo "   After reboot, run this script again to verify the GPU is working."
        echo
        read -p "Do you want to reboot now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Rebooting in 5 seconds... (Press Ctrl+C to cancel)"
            sleep 5
            reboot
        else
            echo "Please reboot manually when convenient."
        fi
    else
        echo "Skipping driver installation."
        echo "To install manually later, run:"
        echo "  sudo apt update"
        echo "  sudo apt install nvidia-kernel-open-dkms"
        echo "  sudo apt remove nvidia-kernel-dkms"
        echo "  sudo reboot"
    fi
fi

echo
echo "Done."
