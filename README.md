# PowerShell AD Management Tool

I built this script to handle the "bread and butter" tasks I ran into while working with Active Directory. Instead of clicking through five menus in ADUC just to reset a password or move a user, this console lets you do it in a few seconds from a single prompt.

## Why I built this
Standard AD management can be slow and prone to typos—especially when you're manually typing out long OU paths. This script automates the repetitive parts (like generating complex temporary passwords) while keeping a log of everything for accountability.

## Key Features
* **Complex Password Gen:** It doesn't just use "Password123". It pulls from four different character sets to make sure it clears AD complexity requirements every time.
* **OU Selection:** Instead of copy-pasting DistinguishedNames, the script pulls a list of available OUs and lets you pick by number.
* **Logging:** Everything is saved to `C:\ADScriptLog.txt`. If a command fails, the script catches the error and logs the specific reason why.

## How it works
1. **Dynamic Domain Detection:** The script finds the domain you're logged into automatically, so the UPNs (username@domain.com) are always correct.
2. **Try/Catch Blocks:** Every action is wrapped in error handling so the script doesn't crash if a user isn't found or permissions are missing.
3. **Color Coded:** I added colors to the terminal so you can easily tell the difference between a success message and an error.

## Usage
1. Open PowerShell as Admin.
2. Run the script: `.\AD_Console.ps1`
3. Follow the menu prompts. 

*Note: You need the RSAT (Active Directory) module installed for this to work.*

---
**Author:** Andrew Storz
