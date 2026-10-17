# Getting started on Height Ritual

A step-by-step guide for teammates who have never used Xcode, iOS development, GitHub or Claude.
You do not need to understand all the code. **Claude writes the code. You decide what to build and
check the result with your own eyes.**

There is also a version of this guide with English, Swedish and Korean, shared as a web page by Chanhee.

- Our GitHub repository: https://github.com/chaneeii/HeightRitual

---

## How work flows

1. You ask Claude for a change, in plain words.
2. Claude edits the code in the project folder on your Mac.
3. You run the app in Xcode and check it in the simulator.
4. Claude puts the change on GitHub as a pull request (PR).
5. Chanhee reviews it and merges it into `main`.

Three rules:

1. **Never push to `main` directly.** Always: new branch, PR, Chanhee reviews, merge.
2. **One thing at a time.** Finish one change, open a PR, then start the next.
3. **Don't say "done" until you have seen it in the simulator.** The camera, the Bluetooth
   controller and the projector do not work in the simulator. If a change touches them, write
   "not tested on a device" in the PR.

---

## Part 1. Install the apps (once, about 1 to 2 hours)

You need a Mac with at least 40 GB of free disk space.

### Step 1. Install Xcode
- Open https://apps.apple.com/app/xcode/id497799835 and click **Get** (or search "Xcode" in the Mac App Store).
- It is large. Start this first and do the other steps while it downloads.
- Open Xcode once. Accept the license, and when it asks which platforms to download, choose **iOS**.

### Step 2. Make a GitHub account
- Sign up at https://github.com/signup.
- Send your username to Chanhee.
- Chanhee invites you. Accept it at https://github.com/chaneeii/HeightRitual/invitations (or from the email).

### Step 3. Install Claude
- Download the desktop app from https://claude.ai/download and sign in.
- You will use the **Code** tab. Claude Code needs a paid Claude plan (Pro or Max).

## Part 2. Set up Terminal (once)

Open **Terminal**: press `⌘ Space`, type `Terminal`, press Return.
Paste each command below and press Return.

### Step 4. Install Homebrew
Homebrew installs developer tools. Copy the install command from https://brew.sh and paste it into Terminal.
It asks for your Mac password; nothing appears while you type, that is normal.
When it finishes, it prints **Next steps** with two or three commands. Run those too.

### Step 5. Install xcodegen and the GitHub tool

```bash
brew install xcodegen gh
```

### Step 6. Log in to GitHub

```bash
gh auth login --web --git-protocol https
```

A code appears in Terminal and a browser page opens. Enter the code there and allow access.
If Terminal asks whether to authenticate Git with your GitHub credentials, answer **Yes**.

## Part 3. Get the project (once)

### Step 7. Clone the repository
"Clone" means copying the project from GitHub to your Mac.

```bash
git clone https://github.com/chaneeii/HeightRitual.git ~/HeightRitual
```

### Step 8. Make the Xcode project and open it

```bash
cd ~/HeightRitual && xcodegen && open HeightRitual.xcodeproj
```

### Step 9. Run the app
1. At the top centre of the Xcode window, click the device name and choose a simulator such as **iPhone 16 Pro**.
2. Click **▶** at the top left, or press `⌘R`.
3. A phone window opens with the app. Your mouse click is a finger tap.
4. Stop with **■**, or `⌘.`

Tips:
- To see the Memory screen without filming anyone: Settings → **Load sample family**.
- Simulator dark mode: `⇧⌘A`. Screenshot: `⌘S`.

### Step 10. Open the project in Claude
In the Claude app, open the **Code** tab, start a new session and choose the `~/HeightRitual` folder.
Always open this folder when you work on the project. Try this first:

> Explain the structure of this project as if I have never done iOS development.
> Show me which files make up one screen.

---

## Part 4. Every task

1. **Start a branch.** *"Get the latest main and make a new branch called feature/memory-empty-state."*
   A branch is your own working copy. `main` stays safe whatever you do.
2. **Ask for the change.** Say what, where, and what success looks like.
   - Too vague: *"Make the memory screen nicer."*
   - Good: *"When Memory has no records, the screen is empty. Add a short message and a button that goes to the Make tab."*
   - Drag a screenshot into the chat when you talk about a screen.
3. **Check it.** Press ▶ in Xcode and try it. If something is off, say so with a screenshot.
   You can also ask: *"Run the tests and tell me if they pass."*
4. **Open a PR.** *"Commit this, push it and open a pull request. Describe what changed and what you checked in the simulator."*
   Send the PR link to Chanhee. If Chanhee leaves comments, show them to Claude and fix them.
5. **After the merge.** *"Switch back to main and get the latest."* Then start again at 1.

---

## Part 5. Running on a real iPhone

- **The simulator needs no certificates, profiles or Apple account.** Most of your work happens there.
- You cannot sign builds with Chanhee's Apple team. It is an individual developer account, and those cannot share signing with other people.
- If you need the app on a phone:
  - Ask Chanhee to install it on a test phone, or to send you a TestFlight build.
  - Or use your own free Apple ID: Xcode → Settings → Accounts → add your Apple ID. Then copy
    `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put in your Team ID and a bundle ID of your own.
    That file is ignored by git, so it never reaches the repository. Apps installed this way stop opening after 7 days; install again.
- If Keychain Access or Certificate Assistant shows an error, you do not need it. Xcode handles certificates itself.

---

## Part 6. Working with Claude

- **Ask anything.** "What is a branch?", "What does this file do?", "Explain what you just did."
- **Plan before big changes.** "Don't change anything yet. Show me your plan first."
- **Stop it when it goes the wrong way.** Interrupt and say what you want instead.
- **Undo.** "Undo all the changes you just made." Easy before a commit.
- Claude asks before running some commands. If you don't know what one does, ask "What does this do?" first.
- If you see a push to `main`, deleting many files, or `--force`, say no and ask Chanhee.
- The project rules are in `CLAUDE.md`. Claude reads them; you don't have to memorise them.

---

## When you are stuck

| Situation | What to do |
|---|---|
| Build error (red mark in Xcode) | Copy the message, paste it to Claude: "Fix this error." |
| Simulator acts strange | Xcode menu Product → Clean Build Folder (`⇧⌘K`), then ▶ again |
| Claude says "conflict" | Someone changed the same lines. "Resolve the conflict and explain what you picked." |
| You think you broke something | Before a commit: "Undo all changes." After a commit: tell Chanhee. `main` is safe. |
| Stuck for more than 30 minutes | Message Chanhee with a screenshot. |

## Words

| Word | Meaning |
|---|---|
| Repository (repo) | The project folder plus its full history |
| Clone | Copy a repository from GitHub to your Mac |
| Branch | A separate line of work. `main` is the official version |
| Commit | A saved snapshot of changes |
| Push / pull | Send your commits to GitHub / get new commits from GitHub |
| Pull request (PR) | A request to merge your branch into `main`. Reviews happen here |
| Merge | Combine a branch into another |
| Build | Turn the code into an app that can run |
| Simulator | A pretend iPhone running on your Mac |
| xcodegen | Makes the Xcode project file from `project.yml` |
