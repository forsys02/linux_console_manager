
# go.sh & go.env User Guide (v1.1) 👨‍💻👩‍💻

## 🧭 Introduction

### What are go.sh and go.env?
- Think of `go.sh` & `go.env` as your personal **command-line remote control** 🕹️ for Linux servers, designed to make your life easier.
- `go.sh` is the **engine** that runs the commands.
- `go.env` is the **customizable menu board** 📜 where *you* define the menus and commands you need.
- Tired of repetitive tasks and complex commands? Just pick a number or a shortcut from your menu, hit Enter, and let `go.sh` handle the rest! 👌
- It feels like a **familiar terminal-based GUI**, making it intuitive even for those newer to the command line.

### Why Should You Use It? 🤔
- **Forget Googling commands** all the time. (Saves precious time! 🍯)
- **Reduce risky typos** like `rm -rf /`. (Server lifeline +1 🙏)
- **Organize your server tasks** logically and visually.
- Build your own **personal command toolkit** for a smoother, faster workflow! ✨

---

## ⚙️ Installation and Execution

### First-Time Setup (Just once!)
```bash
# Download go.sh and run it immediately
wget -O go.sh http://byus.net/go.sh && bash go.sh
```
- If it asks about a missing `go.env` file, just type `y` and hit Enter. It'll download the default menu file for you. Smart, huh? 😉
- After the first run, it usually creates a shortcut (symbolic link) at `/bin/gosh`. This means you can run it from anywhere by simply typing `gosh`!

### Running It Later:
```bash
# If you're in the same directory as go.sh
./go.sh

# From anywhere (if the gosh link was created)
gosh
```
- **Pro Tip 🍯:** Create a file named `go.my.env` in the same directory as `go.sh`. You can put your personal, custom menus in there. It won't get overwritten when you `update` the main script!

---

## ✨ Sneak Peek: What It Looks Like

Running `gosh` will bring up something like this (Black is the background, colors are your menus and info):

![go.sh Screenshot](https://github.com/forsys02/linux_console_manager/blob/defc96351be3597eaf62beede15a21b39e966f8c/eng.png?raw=true)

*(Get the picture? Pretty straightforward! 😉)*

---

## 📋 Basic Controls (Your Remote's Buttons)

This thing is smarter than it looks. Besides numbers, it understands these commands:

| Keystroke(s)   | Function Description                                    | Example           |
| -------------- | ------------------------------------------------------- | ----------------- |
| Number + [Enter] | Execute the corresponding menu item                     | `1` [Enter]       |
| Shortcut + [Enter]| Jump directly to the menu with that shortcut `[key]`  | `p` [Enter]       |
| `m`            | Go directly to the Main Menu                            | `m` [Enter]       |
| `b`            | Go back to the previous menu                            | `b` [Enter]       |
| `bb`, `bbb`    | Go back two or three levels                             | `bb` [Enter]      |
| `<`            | Move to the previous menu at the same level             | `<` [Enter]       |
| `>`            | Move to the next menu at the same level                 | `>` [Enter]       |
| `q`, `0`, `.`  | Exit the current menu / Exit the script                 | `q` [Enter]       |
| `sh`           | Open a temporary shell (inherits bash aliases, functions!)| `sh` [Enter]      |
| `bash`         | Start a completely new bash shell                       | `bash` [Enter]    |
| `conf`         | Edit the main menu file (`go.env`) using vi             | `conf` [Enter]    |
| `confmy`       | Edit your personal menu file (`go.my.env`) using vi     | `confmy` [Enter]  |
| `conff`        | Edit the `go.sh` script itself (for advanced users!)    | `conff` [Enter]   |
| `h`            | Show command execution history (What did I just run? 👀)| `h` [Enter]       |
| `e`            | Launch the text-based file explorer (ranger or built-in)| `e` [Enter]       |
| `update`       | Update `go.sh` and `go.env` to the latest versions      | `update` [Enter]  |
| (Any command)  | Run any Linux command directly!                         | `ls -al` [Enter]  |

---

## 📂 Understanding Menu Structure (`go.env` File)

You can easily create your own menus by editing the `go.env` file. The syntax is simple:

### 1. Creating Main Menu Titles (`%%%`)
```bash
# 'System Info / Process Management' menu, shortcut 'p'
%%% System Info / Process Management [p]
```
- Lines starting with `%%%` become main menu items.
- Add a shortcut key (letters/numbers) inside square brackets like `[p]`.

### 2. Creating Submenus (`{submenu_key}`)
```bash
# 'Advanced Settings' submenu under 'Server Daemons', shortcut 'adv'
%%% {submenu_daemon}>Advanced Daemon Settings [adv]
{submenu_daemon}  # This keyword links menus with the same key!
```
- Add `{submenu_keyname}>` to a main menu title.
- Below it, add a line with just `{submenu_keyname}`. All menu items below this line (until the next `%%%` or blank line) that *also* start with `%%% {submenu_keyname}` will be grouped under the main menu entry.

### 3. Menu Descriptions or Pre-execution Commands (`%%`)
```bash
# Before showing the menu list, print the current directory and date
%% echo "Current Directory: $(pwd)" && date
```
- Lines starting with `%%` are executed *before* the menu items under it are displayed. Great for showing status or calculating values needed for the menu. (Any command works, not just `echo`!)

### 4. Adding Executable Commands
```bash
# Just list the commands you want to run, one per line!
ls -al
pwd
cat /etc/passwd | grep root
```

### 5. Sequential Command Execution (`;;`) - IMPORTANT!
This is a key feature!
- **The Problem:** If you write `ls ; cat varFile` (single semicolon), `bash` might ask you for the `varFile` input *before* the `ls` command even finishes and shows you the file list. Annoying, right?
- **The Solution:** Use `ls ;; cat varFile` (double semicolon). `go.sh` will **execute `ls` completely first**, let you see the output, and *then* prompt you for the `varFile` input for the `cat` command.
- **When to use `;;`:** Use it when you need to **see the result of the first command *before* providing input for the second command**.

```bash
# Example 1: See the file list, then enter a filename to view
ls ;; cat varFile

# Example 2: Find a process ID with ps, then enter the PID to kill it
ps -ef | grep varProcessName ;; kill varPID
```

### 6. English Menu Titles (`%%%e`)
```bash
%%% 시스템 정보 / 프로세스 관리 [p]
%%%e System Information / Process Management [p] # This shows up if the terminal LANG isn't Korean
```
- If you work in multi-language environments, `%%%e` provides an English alternative title automatically.

---

## 💡 Using Input Variables (`varNAME`, `varNAME__DefaultValue`, `varNAME__choice1__choice2`)

Need user input within your commands? Use variables starting with `var`!

### 1. Basic Variable (`varNAME`)
```bash
# Will prompt for an IP address for 'varIP' when executed
ping varIP
```
- Use `var` followed by an **uppercase** letter, then any combination of letters, numbers, or underscores (e.g., `varUserID`, `varPath`).

### 2. Variable with Default Value (`varNAME__DefaultValue`)
```bash
# If you just press Enter, it pings 8.8.8.8
ping varTARGET__8.8.8.8
```
- Add `__` (double underscore) followed by the default value. Pressing Enter uses this default.

### 3. Variable with Choices (`varNAME__choice1__choice2...`)
```bash
# Presents a numbered menu to choose between htop, mc, or ncdu
apt install varPKG__htop__mc__ncdu
```
- List choices separated by `__` after the variable name. This pops up a `select` menu for the user to pick from. This provides *options* to choose from, distinct from a single *default* value.

### 4. Handling Special Characters in Values
Sometimes you need slashes, spaces, etc., in variable *values* or *defaults*. Use these replacements:

- Slash `/` → `@@` (e.g., `varPath__@@etc@@passwd`)
- Space ` ` → `@space@` (e.g., `varMessage__Hello@space@World`)
- Colon `:` → `@colon@`
- Dot `.` → `@dot@`

```bash
# When run, varPath will be converted to /etc/passwd
ls -al varPath__@@etc@@passwd
```

### 5. Conditional Command Execution
```bash
# Only run systemctl start if the varMODE variable is exactly "enable"
[ "varMODE" = "enable" ] && systemctl start varService
```
- You can use standard Bash conditional logic (`[ ]`, `[[ ]]`, `if`).

---

## 🚨 Danger Zone Warning (`!!!`)

```bash
# This will show a confirmation prompt before running!
!!! rm -rf /important/files
```
- Prefixing a command with `!!!` makes `go.sh` ask "Are you sure?" before execution. A great safety net!

---

## 🎁 Built-in Functions (A Taste of Handy Tools)

`go.sh` comes packed with useful functions. Here are a few highlights: ✨

| Function Name | Description                                                     | Example Usage                         |
| ------------- | ------------------------------------------------------------- | ------------------------------------- |
| `vi2 <file>`  | Edits file with vi after auto-backing it up (`.1.bak`, etc.)  | `vi2 /etc/hosts`                      |
| `cdiff <f1> <f2>`| Colorized diff between two files                             | `cdiff hosts hosts.bak`               |
| `cip`         | Colorizes IP addresses in output                              | `ip addr | cip`                       |
| `cpipe`       | Colorizes various patterns (IPs, URLs, paths) in piped output | `cat log.txt \| cpipe`                |
| `pipemenu`    | Turns piped input lines into a numbered selection menu        | `ls \| pipemenu`                     |
| `pipemenu1cancel`| Like `pipemenu`, but selects first word only + Cancel option | `ps aux \| pipemenu1cancel`          |
| `push "msg"`  | Sends a message via your configured Telegram bot            | `df -h \| push`                      |
| `alarm <code> [msg]`| Schedules a Telegram alert (e.g., `alarm 005 "Ramen ready!"`)| `alarm 0010 "10 min break over"` |
| `explorer <dir>`| Launches a text-based file explorer (ranger or built-in)    | `explorer /etc/`                    |
| `ff <func>`   | Displays the source code of a built-in function               | `ff vi2`                              |
| `yyay <pkg>`  | Installs packages using `yum` or `apt` automatically          | `yyay htop mc`                        |
| `rbackup <file>`| Versioned backup like `vi2` (up to 9 versions + dated)      | `rbackup important.conf`            |
| `template_copy <tmpl> <dest>` | Copies a template block from `go.env` to a file | `template_copy lamp.yml config.yml` |
| `insert <file> <keyword>` | Inserts piped text after keyword in file (+backup/diff)| `echo "newline" \| insert file.txt "keyword"` |
| `change <f> <find> <repl>`| Replaces text in file (+backup/diff)              | `change file.txt "old" "new"`         |
| `hash_add <f> <find> [range]`| Comments out line(s) containing find pattern   | `hash_add conf.cfg "debug" +2`      |
| `hash_remove <f> <find> [range]`| Uncomments line(s) containing find pattern | `hash_remove conf.cfg "debug"`    |

*(See the `go.sh` script itself or use `ff <function_name>` to explore more!)*

---

## ✏️ Customization Tips (Make It Yours!)

- **Edit Menus Fast with `conf`:** Opens `go.env` in vi. (`vi2` ensures backups!)
- **Your Private Menu with `confmy`:** Edits `go.my.env`. This file isn't touched by `update`, keeping your personal stuff safe! 👍
- **Sensitive Info (Passwords, Keys)?** Don't put them in `go.env`! Create `~/go.private.env` and add lines like `export DB_PASSWORD='MyS3cr3t!'`. `go.sh` loads this automatically, making `$DB_PASSWORD` available in your commands. (It also sets `chmod 600` for security). 🙅‍♂️
- **Get Notified on Completion:** Add `;; bell ;; push "Job Done!"` after long commands. Get a Telegram ping when it finishes! (Requires setting up `push` first).
- **Create Your Own Functions:** Add custom bash functions to the bottom of `go.sh`, then call them from your `go.env` menus!

---

## 📌 Final Word

Alright folks, you're now equipped to master `go.sh`! 🎉 Open up `go.env` (`conf` command!) and start crafting your perfect command center. Experience how organized and efficient server management can be. Remember to use `update` to get the latest features, and don't hesitate to customize! 😎

> 💡 If you get stuck, check the `help` menu first. If you need more detail on a function, use `ff <function_name>`. Still lost? Ask for help! Your feedback helps make `go.sh` even better! 🙌

---

## ❓ Frequently Asked Questions (FAQ)

*(Anticipating what you might ask...)*

### Q1. My menus are blank! / Things look weird! 😭
A. Could be a syntax error in `go.env` or an encoding mismatch (UTF-8 vs EUC-KR) between your terminal and the file.
   1. Use `conf` to check your `go.env`. Make sure menus start with `%%%`.
   2. If Korean text is broken, try typing `kr` and Enter to toggle encoding.

### Q2. How do I add my own command to the menu?
A. Easy! Use `conf` to edit `go.env`. Find a good spot (or add to the end), leave a blank line, then add:
   ```bash
   # Blank line above is important!

   %%% My Custom Check [check]
   %% My most used commands!
   df -h | grep '/dev/sd'
   free -m
   uptime
   echo "Server looks good!"
   ```
   Save (`ESC` -> `:wq`), exit, and run `gosh` again (or hit `m`). Your new menu will be there!

### Q3. Why use `go.my.env`? Can't I just put everything in `go.env`?
A. You *can*, but `go.env` might get overwritten when you use the `update` command. `go.my.env` is *your* personal space that `update` won't touch. `go.sh` cleverly merges both files when displaying menus, so use `go.my.env` for your custom stuff!

### Q4. How do I handle passwords or API keys securely? 😥
A. **Never** put secrets directly in `go.env`! Create a file `~/go.private.env` and add them like this:
   ```bash
   export API_KEY="abcdef12345"
   export SECRET_PHRASE='My secret phrase!@#' # Use quotes for special chars
   ```
   Then, in `go.env`, use the variables `$API_KEY`, `$SECRET_PHRASE`. `go.sh` loads `go.private.env` automatically and securely (`chmod 600`).

### Q5. How do I set up Telegram notifications? 🤖
A. The first time you use the `push` command (from a menu or the shell), it will prompt you for your Telegram Bot Token and Chat ID. Enter them once, and they'll be saved securely in `~/go.private.env` for future use. (You'll need to create a Telegram bot first - Google can show you how).

### Q6. Can `go.sh` remember the values I enter for variables like `varUSER`?
A. Yes, it does! 😉 If you enter `john` for `varUSER`, the next time it asks for `varUSER`, it will show `Prev.selected value: john`. If there's a default value too, it shows both. Smart, right? (These remembered values are stored in `~/.go.private.var`. You can edit this file using the `editVAR` command).

---

## 🛠️ Practical Scenario: Adding a Quick SSH Connection Menu

Tired of typing `ssh user@host -p port`? Let's menu-fy it!

1.  Run `gosh` and type `confmy` (to edit your personal menu).
2.  When `vi` opens, go to the bottom (press `G`, then `o`) and add this:

    ```bash
    # Add a blank line at the top if needed

    %%% Quick SSH Connections [sshgo]
    %% My favorite servers! One-click connect!
    ssh server1.example.com
    ssh myuser@server2.example.com -p 2222
    assh server3.example.com myuser 'P@$$wOrd!@#' 22
    # 'assh' function auto-handles ID/PW login! (Built-in)
    ```
3.  Save and exit (`ESC`, then type `:wq`, then Enter).
4.  Run `gosh` again or type `m` to go to the main menu. You'll see your new `[sshgo]` menu! Just select the number to connect.

> 😎 How's that? Server management just got a whole lot smoother, right? Hope `go.sh` makes your life easier! 💪 Got more questions or ideas? Let me know! Your feedback is always welcome! 🙌
