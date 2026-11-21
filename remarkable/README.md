# Pink Book on reMarkable

A standalone Qt Quick reader for studying Japanese on an e-ink display. It uses the existing Pink Book chapter annotations for its offline word definitions, readings, grammar explanations and translations. It doesn't start a web browser or require a dictionary service. The website is unchanged. This app branch is based on the deployed `gh-pages` bookshelf and includes all 60 chapters of **霧浜の秘密**, **影の店**, and **最終電車**.

## Reading modes

- **Scroll:** Read vertically through the whole novel. Keep scrolling when a chapter ends.
- **Pages:** Swipe left or right to turn fixed-content pages. Furigana, translations and text size change how the same page is displayed without repaginating the book. If a page is taller than the screen, scroll vertically within it to see the rest.

**Continue Reading** opens the last novel at the saved passage after an app restart. Each book keeps its own reading position. Bookmarks are separate and mark passages you want to revisit.

## Build for reMarkable Paper Pro

1. Confirm the model and firmware under **Settings → Software**. The Paper Pro is named **ferrari** in the SDK; the smaller Paper Pro Move uses **chiappa** and needs its own SDK. Select the exact model and firmware on the [official SDK page](https://developer.remarkable.com/documentation/sdk).
2. Use an x86-64 Linux environment with CMake 3.21 or newer, Node.js 18 or newer and the matching SDK. On a Windows PC, build in a Linux environment and copy the resulting executable to Windows for the USB/SSH transfer if necessary. No tablet access is needed to compile.
3. Install the SDK per reMarkable's directions, then source the installed `environment-setup-…` file in a fresh Bash shell. For example, if you installed a Paper Pro SDK in `~/remarkable-sdk`:

   ```sh
   source ~/remarkable-sdk/environment-setup-cortexa53-crypto-remarkable-linux
   cmake -S remarkable -B build/remarkable -DCMAKE_BUILD_TYPE=Release
   cmake --build build/remarkable --parallel
   file build/remarkable/pink-book-reader
   ```

   Use the environment filename from your SDK if it differs. For Paper Pro, the output of `file` should identify an ARM aarch64 Linux executable, not x86-64. When changing SDKs, use a new build directory. Chapter data is packaged in the application at build time. For dependable Japanese text on the tablet, embed a Japanese font: download [Noto Sans CJK JP Regular](https://github.com/notofonts/noto-cjk/blob/Sans2.004/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf) and add `-DPINK_BOOK_JAPANESE_FONT=/absolute/path/to/NotoSansCJKjp-Regular.otf` to the configure command. The optional font is built into the binary, so there is no runtime download. If you distribute a build with this font, include its [SIL Open Font License](https://github.com/notofonts/noto-cjk/blob/Sans2.004/LICENSE).

## Preview on a computer

From the repo root, in a shell **without** the tablet SDK environment active, install Qt 6.2 or newer development libraries (Qt Core, Gui, QML and Quick) and build in a separate directory:

```sh
cmake -S remarkable -B build/remarkable-desktop
cmake --build build/remarkable-desktop --parallel
ctest --test-dir build/remarkable-desktop --output-on-failure
./build/remarkable-desktop/pink-book-reader
```

To exercise the UI automatically as well, install `PySide6-Essentials` on the host and run `python remarkable/tests/qt-smoke.py`.

A desktop preview checks navigation and content; it does not test panel refresh or touch behavior on a tablet.

## Transfer and run over USB

**Enabling [Developer Mode](https://developer.remarkable.com/documentation/developer-mode) factory-resets the tablet and weakens secure boot.** Follow [reMarkable's backup and Developer Mode instructions](https://support.remarkable.com/s/article/Developer-mode), and verify that your important documents are backed up before enabling it. The reader does not need a writable system partition.

With the tablet connected over USB and its SSH access working, run from the repo root:

```sh
ssh root@10.11.99.1 'mkdir -p ~/pink-book-reader'
scp -O build/remarkable/pink-book-reader remarkable/run-on-tablet.sh root@10.11.99.1:pink-book-reader/
ssh -t root@10.11.99.1 'chmod u+x ~/pink-book-reader/pink-book-reader && sh ~/pink-book-reader/run-on-tablet.sh'
```

`scp -O` selects the older SCP protocol for hosts without an SFTP server. If your SCP client does not recognize `-O` and already uses that protocol, omit the option. If needed, place a Japanese font named `NotoSansJP-Regular.ttf` beside the executable; no system-wide font install is required.

Keep that USB/SSH session open during the first run. The launcher temporarily stops the stock interface, selects the [official Qt e-paper backend](https://developer.remarkable.com/documentation/qt_epaper), and tries to restore the stock interface when you exit or interrupt the process. No boot service or stock app patch is installed. Paper Pro does not use the reMarkable 1/2 touch-rotation settings.

If the tablet stays on a frozen reader screen after the launcher has exited, reconnect over USB and run:

```sh
ssh root@10.11.99.1 'systemctl start xochitl.service && systemctl is-active xochitl.service'
```

If an uncatchable shutdown left `.pink-book-reader.lock` in the app directory, remove the **empty** lock directory with `rmdir ~/pink-book-reader/.pink-book-reader.lock` on the tablet only after confirming the reader and launcher are no longer running. A firmware update can change Qt or the display backend: rebuild with the matching SDK and check the official Qt guide before changing any system files.

## Tablet smoke test

- Open a chapter, tap a Japanese word and a grammar annotation, and dismiss each popup.
- In **Scroll**, scroll past a chapter boundary. In **Pages**, swipe left and right and verify that toggling furigana, translations, or text size doesn't change which passages belong to the page.
- Add a bookmark, exit, reopen, and verify the bookmark and reading position.
- Confirm the stock notebook interface returns after exit, and that offline reading works.
