<img src="assets/icon-256.png" width="96" alt="Margin icon">

# Margin

SAT practice on your own computer: keep a local copy of College Board's public question bank, build quizzes
from the questions you pick, and sit timed adaptive practice tests in a digital-test-style interface.

Two native apps share one design:

| | Folder | Built with |
|---|---|---|
| macOS 26 | `macos/` | Swift, SwiftUI with Liquid Glass, WebKit for question text |
| Windows 10/11 | `windows/` | C#, WPF (.NET 10, Fluent theme), WebView2 for question text |

## Status

Early and lightly tested. The engine (parsing, grading, module assembly, routing, scoring, download and resume)
passes the same self-test in both the Swift and C# versions. The Windows app and its installer compile cleanly
but have had little hands-on use. The macOS SwiftUI screens have been syntax-checked but not yet built in Xcode,
so expect to fix a few compiler errors on the first build. The downloader has been exercised against a stand-in
server, not yet against the live question bank.

## First run

Open **Home** and choose **Download Question Bank**. About 3,800 questions are fetched once (a few minutes) and
stored locally; after that everything except the graphing calculator works offline. The download can be stopped
and resumed, and running it again later only fetches questions you don't have yet.

## Windows

Download `Margin-Setup-<version>.exe` from [Releases](https://github.com/panch076/margin/releases) and run it.
It installs for the current user only (no administrator prompt), adds a Start Menu shortcut, and can be removed
from Settings > Apps. A portable `Margin.exe` is attached to each release too.

The builds are not code-signed, so Windows SmartScreen shows a warning the first time: **More info > Run
anyway**. Question text is drawn with the WebView2 runtime, which ships with Windows 11 and current Windows 10.

To build it, install the .NET 10 SDK and run in `windows/`:

    dotnet run --project Margin.Tests          # engine self-test
    dotnet run --project Margin.App            # run the app
    dotnet publish Margin.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=none -o out

To build the installer, install [NSIS](https://nsis.sourceforge.io) and run in `windows/installer/`:

    makensis -DVERSION=1.0.0 -DEXE=..\out\Margin.exe Margin.nsi

Data lives in `%LOCALAPPDATA%\Margin`. Uninstalling keeps it unless you choose to delete it.

## macOS

Download `Margin-<version>.dmg` from [Releases](https://github.com/panch076/margin/releases), open it and drag
Margin to Applications. It needs macOS 26 and runs on both Apple silicon and Intel Macs.

The app is not signed with an Apple Developer ID, so the first launch is blocked. Open **System Settings >
Privacy & Security**, scroll down to the message about Margin and choose **Open Anyway**.

To build it yourself you need Xcode 26 (or its command line tools). In `macos/`:

    swift run CoreCheck      # engine self-test
    ./make-app.sh            # builds Margin.app in this folder
    ./make-dmg.sh            # packs it into Margin-<version>.dmg

Or open `Package.swift` in Xcode, pick the **Margin** scheme and press Run.

Data lives in `~/Library/Application Support/Margin`.

## Updates

The app checks this repository's latest [release](https://github.com/panch076/margin/releases) when it starts,
and Home has a **Check for updates** button.

- **Windows (installed with the setup program):** Home shows the new version with **Update and restart**. The
  app downloads the new installer, checks it against the size and SHA-256 that GitHub publishes for the file,
  asks before closing, then installs silently and reopens. The question bank and results are kept.
- **Windows (portable exe)** and **macOS:** the new version is announced with a link to the release, where the
  new download is.

Updates are only ever taken from this repository's own release downloads. The builds are not code-signed, so
an update is as trustworthy as the GitHub account that publishes it.

### Releasing a new version

1. Raise the version in `windows/Margin.App/Margin.App.csproj` (`<Version>`) and in
   `macos/Sources/MarginCore/Updater.swift` (`currentVersion`), and push to `main`.
2. On GitHub, open **Actions > Build > Run workflow** and run it on `main`.

That run builds and tests both apps, then publishes the release `v<version>` with the Windows installer, the
portable exe, the macOS disk image and their checksums. Installed Windows copies update themselves from it.
Every ordinary push also runs the build (without publishing), so a broken build shows up early.

## What the test mode does

- Reading and Writing: two modules of 27 questions, 32 minutes each. Math: two modules of 22 questions,
  35 minutes each, with a 10-minute break between sections on a full test.
- Module 1 mixes difficulties. Getting 60% or more right routes you to the higher-difficulty module 2,
  otherwise the lower one. Domain counts per module follow the published test blueprint.
- Tools: mark for review, answer eliminator, question navigator, review page before submitting, hideable clock,
  graphing calculator (Desmos, online) and reference sheet on Math.
- Results: every question with your answer, the correct answer and the explanation; breakdown by domain;
  one-click retry of missed questions.

Two things are approximations, because College Board does not publish them: the routing threshold, and the
200-800 score, which is estimated from each question's difficulty band with a simple statistical model.

## How it is put together

- `shared/question.html` draws one question (passage, choices, typed answers, review mode). Both apps embed it.
  After editing it, run `macos/sync-question-page.sh`; the Windows project picks it up on the next build.
- `MarginCore` (Swift) and `Margin.Core` (C#) are ports of each other: bank storage and download,
  parsing, grading, module assembly, scoring, session flow. Each has the same self-test.
- The bank is stored as `bank.jsonl`, one raw question per line, and parsed at launch.
- The icon is drawn in `assets/icon.svg`; `assets/make-icons.py` exports the `.ico` and `.icns` files.

## Gallery
<img width="2642" height="1718" alt="image" src="https://github.com/user-attachments/assets/0ef5599e-067f-4d42-a3ee-5ec9c5ecdf35" />
<img width="3276" height="1738" alt="image" src="https://github.com/user-attachments/assets/afc25547-1ad4-4d4c-93f4-57d561a15813" />
<img width="3262" height="1714" alt="image" src="https://github.com/user-attachments/assets/8253ac25-1dfb-499f-9bd2-440b7a1be484" />



## Content

The questions belong to College Board and are copied from its public question bank for your own study. Don't
redistribute the downloaded bank. Margin is not affiliated with or endorsed by College Board. SAT is a trademark
of College Board.
