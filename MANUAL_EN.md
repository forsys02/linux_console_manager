# go.sh & go.env: Your Personal Linux Console Swiss Army Knife 🚀

Hey folks! 👋 Ever get tired of typing the same long Linux commands over and over? Or maybe you forget those tricky options and spend ages Googling? "Ugh, there's gotta be a better way!" 😩

Well, **to save your precious time and sanity**, `go.sh` and `go.env` were born! (Okay, maybe I built it for myself first... 😉)

Think of it like your own **customizable cheat sheet on steroids!** It turns your console into a **menu-driven command center**. Define your frequently used or complex commands in the `go.env` file, then execute them simply by selecting a number or a shortcut key. It's like having a universal remote for your Linux server! 🎮✨

This guide will walk you through everything you need to know to become a `go.sh` master – from basic usage to customizing it like a pro! 😎

---

## 🤔 So, What's So Cool About This "Remote" (go.sh)?

*   **No More Memorizing! 🧠➡️🗑️:** Forget long commands and obscure flags. Just add them to your `go.env` **menu** once! Spend less time searching, more time sipping coffee! ☕️
*   **Command Line Tamer! 😱➡️😄:** New to the terminal? No sweat! Just pick a number from the **visual menu**. (Of course, knowing *what* you're selecting is still kinda important! 😉)
*   **Warp Speed with Shortcuts! ⚡️:** Navigate menus and fire off commands blazing fast using custom **shortcuts** like `[p]`, `[dk]`. Leave your colleagues in the dust! 🚀 (You gotta set 'em up first!)
*   **Auto-Fill Magic! ⌨️➡️✨:** Tired of typing the same IPs, paths, or usernames? Set **default values** like `varNAME__defaultValue`! You can even create **multiple-choice menus** like `varNAME__option1__option2`! How cool is that?
*   **DIY Your Menu! 🛠️:** This is YOUR tool! Open up `go.env` and `go.my.env` and add/edit/delete commands to **perfectly match your workflow!** Build the ultimate personalized toolkit! 💪
*   **Telegram Alarms (Optional)! 🔔:** Running a long task? Add `;; bell ;; push "Task Done!"` to the end. Your phone will **ding!** when it's finished! (Requires setup)
*   **Built-in Helpers! 🎁:** Comes packed with handy functions like `vi2` (auto-backup before editing), `push` (send Telegram messages), `alarm` (set timed alerts), `template_copy` (manage command templates), and more! Let the script do the heavy lifting! 😉

---

## ⚙️ How Do I Use This Thing? (Getting Started)

It's super easy!

1.  **First Time Setup (Download & Run):**
    ```bash
    wget -O go.sh http://byus.net/go.sh && bash go.sh
    ```
    *   You'll need `wget` or `curl` installed, obviously. (If not: `apt install wget curl` or `yum install wget curl`)
    *   It might ask if you want to download `go.env` if it's missing. Just hit `y`!
    *   It'll create a handy `/bin/gosh` shortcut (symlink) so you can run it from anywhere later! 👍

2.  **Running It (After the first time):**
    ```bash
    ./go.sh # If you're in the same directory
    # Or use the shortcut from anywhere!
    gosh
    ```

3.  **Controlling the Remote:**
    *   **Select Menu:** Type the number or the shortcut key (`[key]`) shown next to the menu item and press Enter.
    *   **Run Command:** In a command list, type the number of the command you want to run.
        *   If you see a `varNAME` prompt, type the value you need and press Enter. (Or just Enter if there's a default!)
    *   **Navigation:**
        *   `m`: Go straight back to the Main Menu.
        *   `b`: Go back one menu level. (`bb`, `bbb` go back two, three levels!)
        *   `<` or `before`: Go to the previous menu at the same level (useful with sequential shortcuts).
        *   `>` or `next`: Go to the next menu at the same level.
        *   `q` or `0` or `.`: Exit the current menu level, or exit the script from the main menu.
    *   **Shell Access:**
        *   `sh` or `..`: Start an interactive sub-shell that keeps your current environment (aliases, functions work!). History is saved.
        *   `bash` or `...` or `,`: Start a clean, new Bash shell.
    *   **Editing Configs:**
        *   `conf`: Edit the main `go.env` file (uses vi, creates backup).
        *   `confmy`: Edit your personal `go.my.env` file (vi).
        *   `conff`: Edit the `go.sh` script itself (vi).
        *   `confc`, `conffc`: Oops! Revert `go.env` or `go.sh` to the previous backup.
    *   **Other Handy Commands:**
        *   `h`: View and re-run command history.
        *   `e`: Launch file explorer (ranger or built-in). (`ee` goes to `/etc`, `eee` goes to ranger's last path).
        *   `cdr`: Change shell directory to ranger's last path.
        *   `kr`: Force encoding conversion if you see broken Korean characters (or other encoding issues).
        *   `update`: Get the latest version of the script.
        *   **Timer/Alarm:** Enter numbers starting with `0` (e.g., `05`=5s, `0010`=10m, `00001800`=18:00) + message (requires atd, Telegram optional).

---

## 3. File Structure

*   **`go.sh`**: The main executable script. Contains all the logic.
*   **`go.env`**: The **core configuration file** where you define your menu structure and commands. (Plain text)
*   **`go.my.env` (Optional):** For your custom menus. Merged after `go.env`.
*   **`~/go.private.env` (Optional):** Stores sensitive info like API keys, passwords. (`VARNAME=value` format, recommend `chmod 600`) Loaded automatically.
*   **`~/.go.private.var` (Auto-generated):** Saves the last used values for `varNAME` variables for reuse.
*   **`/tmp/go_history.txt` or `~/tmp/go_history.txt` (Auto-generated):** Stores command execution history.

---

## 4. Getting Started

1.  **First Time Setup (Download & Run):**
    ```bash
    wget -O go.sh http://byus.net/go.sh && bash go.sh
    ```
    *   You'll need `wget` or `curl` installed, obviously. (If not: `apt install wget curl` or `yum install wget curl`)
    *   It might ask if you want to download `go.env` if it's missing. Just hit `y`!
    *   It'll create a handy `/bin/gosh` shortcut (symlink) so you can run it from anywhere later! 👍

2.  **Running It (After the first time):**
    ```bash
    ./go.sh # If you're in the same directory
    # Or use the shortcut from anywhere!
    gosh
    ```

---

## 5. Usage (Controlling the Remote)

*   **Select Menu:** Type the number or the shortcut key (`[key]`) shown next to the menu item and press Enter.
*   **Run Command:** In a command list, type the number of the command you want to run.
    *   If you see a `varNAME` prompt, type the value you need and press Enter. (Or just Enter if there's a default!)
*   **Navigation:**
    *   `m`: Go straight back to the Main Menu.
    *   `b`: Go back one menu level. (`bb`, `bbb` go back two, three levels!)
    *   `<` or `before`: Go to the previous menu at the same level (useful with sequential shortcuts).
    *   `>` or `next`: Go to the next menu at the same level.
    *   `q` or `0` or `.`: Exit the current menu level, or exit the script from the main menu.
*   **Shell Access:**
    *   `sh` or `..`: Start an interactive sub-shell that keeps your current environment (aliases, functions work!). History is saved.
    *   `bash` or `...` or `,`: Start a clean, new Bash shell.
*   **Editing Configs:**
    *   `conf`: Edit the main `go.env` file (uses vi, creates backup).
    *   `confmy`: Edit your personal `go.my.env` file (vi).
    *   `conff`: Edit the `go.sh` script itself (vi).
    *   `confc`, `conffc`: Oops! Revert `go.env` or `go.sh` to the previous backup.
*   **Other Handy Commands:**
    *   `h`: View and re-run command history.
    *   `e`: Launch file explorer (ranger or built-in). (`ee` goes to `/etc`, `eee` goes to ranger's last path).
    *   `cdr`: Change shell directory to ranger's last path.
    *   `kr`: Force encoding conversion if you see broken Korean characters (or other encoding issues).
    *   `update`: Get the latest version of the script.
    *   **Timer/Alarm:** Enter numbers starting with `0` (e.g., `05`=5s, `0010`=10m, `00001800`=18:00) + message (requires atd, Telegram optional).

---

## 6. `go.env` Syntax Guide (Building Your Own Remote Control!)

This is where the magic happens! Open `go.env` and start customizing. The syntax is easy:

*   **Main Menu Item (`%%%`):** Top-level entry.
    ```
    %%% System Info [p]
    ```
    *   Starts with `%%%`. `[shortcut]` is optional for quick access.

*   **English Title (Optional / `%%%e`):** Displays for non-Korean environments.
    ```
    %%%e System Info [p]
    ```
    *   Starts with `%%%e`. The shortcut should be the same.

*   **Pre-Execution Command (Optional / `%%`):** Runs *before* the menu list shows.
    ```
    %% echo "Showing current system info..."
    ```
    *   Starts with `%%`. Good for descriptions or status checks.

*   **Submenu Definition (`%%% {submenu_...}>`):** Group related commands.
    ```
    %%% {submenu_web}> Web Server Management [web]
    ```
    *   `{submenu_tagname}`: An identifier for this group.
    *   `>`: Separates the tag from the title.

*   **Linking Menus (Submenu Entry):**
    ```
    %%% Server Management [s]
    {submenu_web}  # Selecting 's' jumps to the {submenu_web} menu
    {submenu_db}
    ```
    *   Place the `{submenu_tagname}` below a main menu item.

*   **Defining Commands (The Action!):**
    *   List commands or functions one per line below the menu title.
    *   **Sequential Execution (` ;; `):** Chain commands.
        ```bash
        cd /tmp ;; pwd ;; ls -al
        ```
    *   **User Input Variables (`varNAME`):**
        ```bash
        echo "Your input: varMY_INPUT" # Prompts for [varMY_INPUT]:
        ping varTARGET_IP__8.8.8.8 # Default value 8.8.8.8
        apt install $(echo "nginx__apache2__httpd" | pipemenu1cancel) # Selection menu!
        # Use @@ for / in paths (e.g., varPATH__@@etc@@passwd)
        # Use @space@ for spaces (displays as _)
        # Use @colon@ for :
        # Use @dot@ for .
        ```
    *   **Warning Prompt (`!!!`):** Confirms before running potentially risky commands.
        ```bash
        !!! rm -rf /important/files
        ```
    *   **Comment/Description Line (`:`):** Just text, won't execute.
        ```
        : This is just a description.
        ls -al # This command will run.
        ```

*   **Ending a Menu Group (Blank Line!):** **Crucial!** Put an empty line between `%%%` menu groups.

*   **Comments (`#`):** Lines starting with `#` are ignored. Comments after commands (`# like this`) are automatically removed.

---

## 7. Handy Built-in Functions (A Taste)

`go.sh` includes useful functions you can call directly in your commands:

*   `vi2 <file> [search_term]`: Opens file in vi/vim after creating a backup. Jumps to `search_term` if provided.
*   `rbackup <file1> [file2...]`: Creates rotated backups (`.1.bak`, `.2.bak`...).
*   `rollback <file>`: Restores a file from its latest `rbackup`.
*   `cdiff <file1> <file2>`: Shows differences between two files in color.
*   `cip`, `cip24`, `cip16`: Colorizes IP addresses (grouped by subnet).
*   `cgrep`, `cgrep1`, `cgrepl`, `cgrepline`, `cgrepn`: Highlights search terms or lines.
*   `pipemenu`, `pipemenu1`, `pipemenulist`: Turns piped input into a selection menu.
*   `template_copy <name> <dest>`: Copies a predefined template (from `go.sh` itself) to a destination file.
*   `template_view <name>`: Views a template's content.
*   `template_edit <name>`: Edits a template's content (vi).
*   `push [message]`: Sends a message via Telegram bot (requires setup).
*   `alarm <timecode> [message]`: Schedules an alarm message (requires `atd`).
*   `saveVAR`, `loadVAR`: Saves/loads `varNAME` values between sessions.
*   `explorer <path>`: Opens a terminal file explorer (ranger if installed).
*   `ff <func_name>`: Shows the source code of a built-in function (for learning/debugging).

(Explore the `go.sh` file to discover more functions!)

## ⚠️ Heads Up! (Important Notes)

*   **Run Commands at Your Own Risk! 😬:** You are responsible for the commands you put in `go.env`. Be careful, especially with `!!!` commands or anything involving `rm -rf`!
*   **Password Security! 🔒:** **Never** hardcode passwords directly in `go.env` or `go.sh`. Use the `~/go.private.env` file (`VAR=value` format) and set its permissions to `600` (`chmod 600 ~/go.private.env`).
*   **Bugs Happen! 🤔:** While tested, this script might have unexpected behavior. Always back up important data before running critical commands.
*   **Dependencies! 🛠️:** Some commands need external packages (`wget`, `htop`, `ranger`, etc.). The `yyay`, `ay`, `yy` functions might help install them on Debian/CentOS-based systems.

---

*Hope this script becomes your trusty sidekick on your Linux server adventures!*
*Feel free to reach out if you have questions or ideas for improvement.*
