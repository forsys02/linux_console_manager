```markdown
# go.sh: Your Command-Line Swiss Army Knife for Linux Server Management 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Maintenance](https://img.shields.io/maintenance/yes/2024)](https://github.com/your-github-username/go.sh) <!-- Replace with your repo link -->
[![Bash Shell Compatible](https://img.shields.io/badge/Bash-v2+-brightgreen.svg)](https://www.gnu.org/software/bash/)

**Effortlessly manage your Linux servers right from your terminal with `go.sh`, a powerful and customizable menu-driven bash script.**

Tired of memorizing complex commands?  Wish you had a streamlined way to handle common server administration tasks?  `go.sh` is here to simplify your life.  It provides a user-friendly, text-based interface to a wide range of essential server management functions, all accessible with a few keystrokes.

## ✨ Key Features

`go.sh` is packed with features designed to make server administration a breeze:

**System Information & Process Management:**

* **Comprehensive System Overview:**  Quickly retrieve system information like hostname, IP addresses (local & public), uptime, kernel version, and resource usage.
* **Process Monitoring & Control:**  Manage processes with tools like `top`, `htop`, `bashtop`, and `iftop` directly from the menu.
* **Process Exploration:**  Dive deep into process trees (`pstree`) and find detailed information with `ps` and `lsof`.
* **Process Termination:**  Easily kill processes by PID, user, or search criteria, with safety checks to prevent accidental system-critical process termination.
* **Resource Optimization:**  Utilize `renice` and `ionice` to adjust process priorities.
* **Login History & Network Stats:**  Review login history (`last`), monitor network connections (`netstat`, `nmap`).

**Server & Daemon Management:**

* **Daemon Status & Control:**  List, start, stop, restart, enable, and disable systemd services.
* **Service Exploration:**  Inspect service configurations and dependencies.
* **Firewall Management:**  Open firewall ports for specific services.
* **Daemon Management Utilities:**  Access classic daemon management tools like `sysv-rc-conf`, `systemctl-ui`, and `ntsysv`.

**Package Management (Yum/Apt & More):**

* **Package Detection:** Automatically detects available package managers (`yum`, `dnf`, `apt`, `pkginfo`, `dpkg`, `rpm`).
* **Package Installation & Removal:**  Install and remove packages effortlessly.
* **Package Updates & Upgrades:**  Keep your system up-to-date with package updates.
* **Package Information:**  List installed packages, search for packages, and explore package contents.
* **Repository Management:**  Easily edit repository configuration files (`sources.list`, `yum.conf`).

**User & Environment Management:**

* **User & Group Administration:**  Add, modify, and delete users and groups.
* **Password Management:**  Set and change user passwords, lock/unlock accounts.
* **Permission & Ownership Control:**  Manage file and directory permissions and ownership (`chown`, `chmod`).
* **Environment Variable Configuration:**  Easily view and modify environment variables.
* **User Account Auditing:**  Identify system accounts, user accounts, and locked accounts.

**Logging & File Management:**

* **System Log Exploration:**  View system logs (`dmesg`, `journalctl`, `/var/log/messages`, etc.) with filtering and real-time monitoring.
* **Open File Management:**  List open files and network connections (`lsof`).
* **Log File Browsing:**  Quickly browse and tail recent log files.
* **File System Utilities:**  Mount/unmount file systems, check disk space (`df`), test HDD speed (`hdparm`), and manage partitions (`fdisk`, `parted`).

**Network Management & Security:**

* **Network Information:**  Display network interfaces, IP addresses, routing tables, and connection statistics.
* **Network Configuration:**  Edit network configuration files (`ifcfg-*`, `interfaces`, `netplan.yml`, `resolv.conf`).
* **Network Restart:** Safely restart network services on Debian, CentOS, and Ubuntu systems, with backup and rollback capabilities.
* **Firewall Management (Iptables/UFW):** Basic firewall control and rule management.
* **DDoS Attack Mitigation:**  Tools to identify and block potential DDoS attackers based on connection counts, with IP whitelisting and blacklist management.
* **Network Monitoring:**  Real-time network traffic monitoring with `iftop`.

**Backup & Cloud Management:**

* **Local & Remote Backup:**  Comprehensive backup solutions using `tar`, `rsync`, and `lftp` for local and remote backups.
* **Incremental & Full Backups:**  Supports both incremental and full backup strategies.
* **Database Backups:**  Easily dump all MySQL databases.
* **Cloud Storage Integration:**  Seamlessly integrate with cloud storage providers using `rclone` for mounting and direct command-line access.
* **Server-to-Server Transfers:**  Efficiently transfer files and folders between servers using `ncp`, `ncpr`, and compressed transfer options (`ncpzip`, `ncpzipupdate`).

**Virtualization & Containerization (Proxmox, KVM, Docker):**

* **Proxmox Management:**  Extensive Proxmox VE management tools including VM/CT listing, starting, stopping, cloning, backup/restore, GPU passthrough, and more.
* **KVM Hypervisor Management:** Basic KVM VM management using `virsh` and `virt-install`.
* **Docker Management:**  Docker container and image management, `docker-compose` integration with pre-configured setups for popular applications (WordPress, Nextcloud, Rocket.Chat, etc.).
* **Minecraft Server Management:**  Simplified setup and management of Minecraft servers (Paper, Forge, BungeeCord).

**Utilities & Tools:**

* **File Explorers:**  Menu-driven access to powerful terminal file explorers like `ranger`, `lfm`, `mc`, `vifm`, and `nnn`.
* **Screen & Tmux Session Management:**  Effortlessly manage `screen` and `tmux` sessions.
* **Vim Configuration:**  Quickly access and customize your `.vimrc` configuration.
* **Swap Space Management:**  Manage swap space (on/off, size adjustment).
* **Cron & At Job Scheduling:**  Schedule tasks using `at` and `cron`.
* **Fail2ban Management:**  Basic Fail2ban status and manual IP banning.
* **MySQL Query Tools:**  Basic MySQL administration and query execution.
* **Find & Search Utilities:** Powerful file searching and content searching tools.
* **Device-Mapper Management:** Tools for managing device-mapper (LVM) devices.
* **Emergency Recovery & Booting Tools:**  Utilities for system recovery, GRUB configuration, and boot management.
* **Language & Timezone Settings:**  Easily configure system locale, timezone, and hostname.
* **Security & Permission Hardening:**  Tools to enhance server security by adjusting file permissions and ownership.
* **Web Management Solutions (Webmin/Cockpit):**  One-click installation for web-based server management panels.
* **Network Tools (NFS, iSCSI, AutoFS, Open-vSwitch):**  Simplified configuration for network file sharing and virtualization technologies.
* **And much more!**  See the `go.env.txt` file for the full menu.

## 🚀 Getting Started

1. **Download `go.sh` and `go.env.txt`:**
   ```bash
   wget http://byus.net/go.sh
   wget http://byus.net/go.env
   chmod +x go.sh
   chmod 600 go.env
   ```

2. **Make it Executable from Anywhere (Optional):**
   ```bash
   sudo ln -s "$(pwd)/go.sh" /bin/go
   ```
   Now you can simply type `go` in your terminal to launch the menu.

3. **Run `go.sh`:**
   ```bash
   ./go.sh
   # or if you created the symlink:
   go
   ```

4. **Explore the Menu:** Use the number keys or shortcut letters (shown in `[]`) to navigate the menu.

## ⚙️ Configuration (`go.env.txt`)

The power of `go.sh` lies in its customizable configuration file, `go.env.txt`.  Here's how you can tailor it to your needs:

* **Menu Structure:**  Define your main menu and submenus using `%%%` to start a menu section and blank lines to separate menu items. Submenus are created by nesting menu sections.
* **Comments:** Lines starting with `#` are treated as comments and are ignored by the script. Use these to add notes and explanations within your `go.env.txt`.
* **Commands:**  Each menu item executes the commands listed below it (until the next `%%%` or blank line).  Use standard bash commands.
* **Variables:** Use `varVARIABLE_NAME__default_value` to define variables that users can input directly from the menu.  Default values are provided for convenience.
* **Submenus:** Create nested menus using `%%% {submenu_shortcut}Menu Title [shortcut]` and `%%%e {submenu_shortcut}English Menu Title [shortcut]` for multilingual support.
* **English Menu:**  Use `%%%e` for menu titles and commands that should be displayed when the system locale is not Korean.
* **Custom Functions:**  Extend `go.sh` by adding your own bash functions at the end of the `go.sh.txt` file and calling them from your menu items.
* **`conf` Command:**  From the main menu or any submenu, type `conf` and press Enter to directly edit the `go.env.txt` file using `vi`.

**Example `go.env.txt` Snippets:**

```txt
# System Information Menu
%%% 시스템 정보 / 프로세스 관리 [s]
%%%e System Information / Process Management [s]
%% uname -a ;echo
%% echo "Hostname: $(hostname)"
%% w
```

```txt
# Submenu Example
%%% 시스템 관리 [m]
%%%e System Management [m]
{submenu_sys}

%%% {submenu_sys}네트워크 설정 [net]
%%%e {submenu_sys}Network Settings [net]
%% vi2 /etc/network/interfaces
%% systemctl restart networking
```

## ⌨️ Usage

* **Navigation:** Use number keys (1, 2, 3...) or shortcut letters (`[a]`, `[b]`, `[c]`, etc.) to select menu items.
* **Submenus:** Navigate deeper into submenus using their shortcut letters.
* **Command Execution:**  Selected menu items execute the commands defined in `go.env.txt`.
* **Variable Input:** When a menu item with variables is selected, you'll be prompted to enter values for each variable.  Press Enter to use the default value.
* **Confirmation:** For "dangerous" commands (marked with `!!!`), you'll be asked for confirmation before execution.
* **Easter Egg:** Type `..` in the main menu to access a direct command-line interface with your `.bashrc` aliases loaded.
* **`conf` Command:** Type `conf` to edit `go.env.txt` directly.
* **Exit:** Type `0` or `q` in the main menu to exit `go.sh`.

## ⚙️ Variables: Customize Your Commands

`go.sh` uses a simple variable system to make commands more dynamic and reusable.

* **Syntax:** `varVARIABLE_NAME__default_value`
    * `var`:  Indicates a variable.
    * `VARIABLE_NAME`:  The name of your variable (e.g., `PACKAGE`, `PORT`, `HOST`).
    * `__default_value`: (Optional) A default value that will be used if you don't provide input. Use `@@` for `/` in default paths.

* **Example:**
   ```txt
   %%% 패키지 설치 [i]
   %%%e Install Package [i]
   yum install -y varPACKAGE__nginx
   ```
   When you select this menu item, you'll be prompted to enter a value for `PACKAGE`. If you just press Enter, it will default to `nginx`, and the command `yum install -y nginx` will be executed.

## 💡 Tips and Tricks

* **Multilingual Support:** `go.sh` intelligently detects your locale and displays menus in Korean or English based on your system settings. You can force a language by setting the `envko` variable in `~/go.private.env` to `utf8` or `euckr`.
* **Hidden Menus:**  Create hidden submenus using `%%% {submenu_hidden}`. These menus won't be directly listed in the main menu but can be accessed via their shortcut keys or by calling them from other menu items.
* **Command History:**  `go.sh` keeps a history of your executed commands in `/tmp/go_history.txt`. Use the `h` shortcut in menus to view and re-execute recent commands.
* **Direct Command Input (Easter Egg):**  Type `..` in the main menu to enter a direct command-line mode where you can type any bash command and utilize your `.bashrc` aliases.
* **Custom Functions:**  Extend `go.sh` by adding your own bash functions to the `go.sh.txt` file. You can then call these functions directly from your menu items, creating powerful and specialized tools.
* **`conf` Command Workflow:** Use the `conf` command to quickly edit `go.env.txt` directly from the menu. This is much faster than manually opening the file in `vi`.

## 🤝 Contributing

`go.sh` is a labor of love, and contributions are always welcome!  If you have ideas for new features, improvements, bug fixes, or want to add more menu items, please feel free to:

* **Fork this repository.**
* **Create a branch for your changes.**
* **Submit a pull request.**
* **Report issues and suggest enhancements in the "Issues" tab.**

Your feedback and contributions are highly appreciated!

## 🧑‍💻 Author & Contact

* **Author:** 손희태 (Son Heetae) - Byus.net
* **Contact:** forsys02@gmail.com, KakaoTalk: byusnet

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Enjoy simplifying your server management with `go.sh`!** 🚀
```

**How to use the downloadable file:**

1.  **Download:** Click the link above and save the `README.md` file to your computer.
2.  **GitHub Repository:** Navigate to the root directory of your `go.sh` GitHub repository.
3.  **Upload/Replace:**
    *   **If you don't have a `README.md` yet:** Simply upload the downloaded `README.md` file to your repository.
    *   **If you already have a `README.md`:** Replace your existing `README.md` file with the downloaded one. You can do this by uploading the new file and overwriting the old one, or by copying the content from the downloaded file and pasting it into your existing `README.md` file (using GitHub's web editor or a local text editor).

Remember to replace the placeholder links and information (like `your-github-username`, email, etc.) in the `README.md` file with your actual details after uploading.

Let me know if you have any other questions!
