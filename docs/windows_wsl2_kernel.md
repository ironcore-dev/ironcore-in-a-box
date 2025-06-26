# Compiling a Custom WSL2 Kernel for IronCore in a Box

## Overview

The default kernel provided by Microsoft for WSL2 may not include certain networking modules (lwtunnel, lwtunnel_bpf, ipv6_tunnel) required by IronCore. This guide provides step-by-step instructions on how to compile a custom WSL2 kernel with these necessary modules enabled.

**Note:** These steps are performed inside your WSL2 distribution (e.g., Ubuntu).

## Prerequisites

Before you start compiling, ensure you have the necessary build tools installed in your WSL2 environment. For Debian/Ubuntu-based distributions, you can install them using:

```bash
sudo apt update
sudo apt install -y build-essential flex bison libssl-dev libelf-dev bc dwarves git libncurses-dev rsync
```

Adjust the package names if you are using a different distribution (e.g., dnf or zypper for Fedora/openSUSE).

## Steps

1.  **Clone the WSL2 Kernel Repository:**
    Open your WSL2 terminal and clone the official Microsoft WSL2 Linux Kernel repository:
    ```bash
    git clone https://github.com/microsoft/WSL2-Linux-Kernel
    cd WSL2-Linux-Kernel
    ```
    

2.  **Identify Your Current Kernel Version:**
    Find the exact version tag you need to check out. Run uname -r in your WSL2 terminal:
    ```bash
    uname -r
    ```
    
    You might see output similar to 5.15.167.4-microsoft-standard-WSL2+.

3.  **Checkout the Correct Kernel Source Tag:**
    The git tag name often slightly differs from the uname -r output. You need to map the uname -r output to the corresponding tag in the git repository. For the example above (5.15.167.4-microsoft-standard-WSL2+), the tag is likely linux-msft-wsl-5.15.167.4.
    * Check available tags using git tag.
    * Checkout the tag matching your version:
        ```bash
        # Example: Use the version identified in the previous step
        git checkout linux-msft-wsl-5.15.167.4
        ```
        
        **Important:** Replace linux-msft-wsl-5.15.167.4 with the exact tag corresponding to *your* kernel version from uname -r.

4.  **Copy Your Current Kernel Configuration:**
    Use the configuration of your currently running kernel as a base:
    ```bash
    cat /proc/config.gz | gunzip > .config
    ```

5.  **Prepare for Build:**
    Prepare the kernel source tree using the copied configuration:
    ```bash
    make prepare
    make modules_prepare
    ```

6.  **Enable Required Kernel Options:**
    You need to enable CONFIG_LWTUNNEL, CONFIG_LWTUNNEL_BPF, and CONFIG_IPV6_TUNNEL. You can do this using the interactive menu configuration or by directly editing the .config file.

    * **Using menuconfig (Recommended):**
        ```bash
        make menuconfig
        ```
        Navigate through the menu (use / to search):
        * Find CONFIG_LWTUNNEL (likely under Networking support -> Networking options -> Lightweight tunnels) and enable it as a module (M).
        * Find CONFIG_LWTUNNEL_BPF (likely nearby CONFIG_LWTUNNEL) and enable it as a module (M).
        * Find CONFIG_IPV6_TUNNEL (likely under Networking support -> Networking options -> IPv6: IP-in-IP tunnel (RFC2473)) and enable it as a module (M).
        Save the configuration and exit.

    * **Editing .config directly (Advanced):**
        Open the .config file in a text editor (like nano or vim) and ensure the following lines exist or are modified as shown. If they don't exist, add them.
        text
        CONFIG_LWTUNNEL=m
        CONFIG_LWTUNNEL_BPF=m
        CONFIG_IPV6_TUNNEL=m
        
        Save the file after making the changes.

7.  **Compile the Kernel:**
    Compile the kernel. This process can take a significant amount of time. Using -j$(nproc) utilizes all available CPU cores to speed it up.
    ```bash
    make -j$(nproc)
    ```
    The resulting kernel image is typically created as arch/x86/boot/bzImage or sometimes vmlinux in the root of the source directory. We'll assume the final file is vmlinux in the root for the next steps, as mentioned in the initial request. Double-check the build output if you can't find it.

8.  **Install Kernel Modules:**
    Install the newly compiled modules into your WSL2 filesystem:
    ```bash
    sudo make modules_install
    ```

9.  **Copy the Compiled Kernel to a Windows Location:**
    The compiled kernel file (vmlinux or arch/x86/boot/bzImage) needs to be accessible from Windows. Copy it to your Windows user's directory (accessible via /mnt/c/Users/<YourWindowsUsername>/ in WSL2).
    * **Important:** Replace &lt;YourWindowsUsername&gt; with your actual Windows username.
    * **Important:** Ensure the destination path (C:\Users\<YourWindowsUsername>\) exists. You might want to create a specific folder, e.g., C:\wsl-kernels\.

    Example copying vmlinux to C:\Users\<YourWindowsUsername>\vmlinux:
    ```bash
    # Assuming the compiled kernel is named 'vmlinux' in the current directory
    cp vmlinux /mnt/c/Users/<YourWindowsUsername>/vmlinux

    # OR if the kernel is bzImage and you want to place it in C:\wsl-kernels\
    # mkdir -p /mnt/c/wsl-kernels
    # cp arch/x86/boot/bzImage /mnt/c/wsl-kernels/ironcore-kernel
    ```
    Choose a clear path and filename on the Windows side. Let's assume you copied it to C:\Users\<YourWindowsUsername>\vmlinux for the next step.

10. **Configure WSL2 to Use the Custom Kernel:**
    * **Shutdown WSL:** Open **Windows PowerShell** or **Command Prompt** (not inside WSL2) and run:
    ```powershell
        wsl --shutdown
    ```
 
    * **Create/Edit .wslconfig:** Create or edit the file named .wslconfig directly in your Windows user profile directory (%USERPROFILE%, usually C:\Users\<YourWindowsUsername). Add the following content, adjusting the kernel= path to where you copied your compiled kernel file. **Use double backslashes (\\) for the path in this file.**

    ```ini
        [wsl2]
        kernel=C:\\Users\\<YourWindowsUsername>\\vmlinux
        # Example if you used C:\wsl-kernels\ironcore-kernel:
        # kernel=C:\\wsl-kernels\\ironcore-kernel
    ```

    Save the .wslconfig file. Make sure it's saved with UTF-8 encoding if using Notepad.
11. **Restart WSL:**
    Restart your WSL distribution from PowerShell or CMD:
    ```powershell
    wsl -d <YourDistroName>
    # Example: wsl -d Ubuntu
    ```
    Alternatively, just launching your WSL distribution from the Start Menu should work.

12. **Verify (Optional but Recommended):**
    Once WSL restarts, check if the required modules can be loaded:
    ```bash
    # Check if modules exist and load them manually
    sudo modprobe lwtunnel_bpf
    sudo modprobe ip6_tunnel

    # List loaded modules to confirm
    lsmod | grep lwt
    lsmod | grep ip6_tunnel
    ```
    
    If these commands run without errors, your custom kernel is likely working correctly with the necessary modules. You can now proceed with the make up command for ironcore-in-a-box.

    You can also check uname -r again; while the version string might look similar, it's now running your custom compiled code.

## Troubleshooting

* **Build Errors:** Ensure all prerequisites (build-essential, etc.) are installed. Double-check that you checked out the correct kernel tag.
* **WSL Not Starting:** Verify the path in .wslconfig is correct, uses double backslashes (\\), and points to the actual compiled kernel file. Try a simpler path like C:\\vmlinux. Ensure the kernel file wasn't corrupted during copy.
* **Modules Not Loading:** Double-check that you enabled the correct CONFIG_ options (=m) during make menuconfig or in the .config file and that sudo make modules_install completed successfully.
