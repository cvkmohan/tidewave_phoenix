# Installation

Tidewave is the coding agent for full-stack web app development. Integrate Claude Code, OpenAI Codex, and other agents with your web app and web framework at every layer, from UI to database. [See our website](https://tidewave.ai) for more information.

> **Note:** This is a fork of the original Tidewave project with additional features including browser testing tools powered by Lightpanda.

## Installing the app

To get started with Tidewave, download our desktop app:

* For macOS: [Apple Silicon](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-app-aarch64.dmg), [Intel](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-app-x64.dmg)
* For Linux: [AppImage (x86_64)](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-app-amd64.AppImage), [AppImage (ARM64)](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-app-aarch64.AppImage)
* For Windows: [Windows](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-app-x64.exe)

After installation, an icon should appear in your menu bar (top-right on macOS and Linux, bottom-right on Windows).

We also offer a [CLI](#cli) if you are running your application remotely, inside containers, or other cases where the desktop application is not an option. If you are using Docker, read [our containers guide](../guides/containers.md).

## Running Tidewave

After installation, you can run the Tidewave application. By default, it will run a service on [`http://localhost:9832`](http://localhost:9832), which you can acess from your favorite browser. Once you do, you will be greeted with this screen:

![Welcome to Tidewave Web](assets/tidewave-app.png)

Then you can put the address of your web application and Tidewave will connect to it. If your web application was not yet configured with Tidewave, you will be prompted to do so, using the links below:

* [Tidewave for Django](https://github.com/tidewave-ai/tidewave_python#django)
* [Tidewave for FastAPI](https://github.com/tidewave-ai/tidewave_python#fastapi)
* [Tidewave for Flask](https://github.com/tidewave-ai/tidewave_python#flask)
* [Tidewave for Next.js](https://github.com/tidewave-ai/tidewave_js#nextjs)
* [Tidewave for Phoenix](https://github.com/tidewave-ai/tidewave_phoenix)
* [Tidewave for Ruby on Rails](https://github.com/tidewave-ai/tidewave_rails)
* [Tidewave for TanStack Start](https://github.com/tidewave-ai/tidewave_js#tanstack-start)
* [Tidewave for Vite](https://github.com/tidewave-ai/tidewave_js#vite)

The Tidewave app will remain running on your menu bar (top right on macOS/Linux, bottom right on Windows), you can click it to open up, configure, and update Tidewave.

Remember Tidewave must always run on the same machine as your web server is running. If your web server is running on a separate machine, you will want to use our CLI.

## CLI

For running Tidewave inside containers and other advanced uses, a CLI is also available:

* For macOS: [Apple Silicon](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-aarch64-apple-darwin), [Intel](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-x86_64-apple-darwin)
* For Windows: [Windows](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-x86_64-pc-windows-msvc.exe)
* For Linux: [aarch64-gnu](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-aarch64-unknown-linux-gnu), [aarch64-musl](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-aarch64-unknown-linux-gnu), [x86_64-gnu](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-x86_64-unknown-linux-gnu), [x86_64-musl](https://github.com/tidewave-ai/tidewave_app/releases/latest/download/tidewave-cli-x86_64-unknown-linux-musl)

Once the CLI is installed, run it with `./tidewave`. Run `./tidewave --help` for a list of all options. 

For security reasons, the CLI only allows access from the same machine it is running on by default. Furthermore, it enforces that the CLI is being accessed from `localhost` or `127.0.0.1`. If you want to run the CLI on a custom server, you must pass `--allow-remote-access` and `--allowed-origins=https://HOSTNAME:PORT` respectively to change our defaults. You can also [enable HTTPS certificates](../guides/https.md) both for the App and the CLI.

Both [our App and CLI are open source](https://github.com/tidewave-ai/tidewave_app).

## Optional: Install Lightpanda Browser

This fork includes enhanced browser testing capabilities using [Lightpanda](https://lightpanda.io/), a lightweight headless browser designed for AI and automation. When installed, Tidewave can:

- Execute JavaScript and verify client-side behavior
- Test Phoenix LiveView hooks and JavaScript interactions
- Detect console errors during page loads
- Perform full DOM inspection with source annotations

### Installing Lightpanda

**From Nightly Builds (Recommended):**

*For Linux x86_64:*
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

*For macOS (Apple Silicon):*
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

*For macOS (Intel):*
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-macos && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

**Using Docker:**
```bash
docker run -d --name lightpanda -p 9222:9222 lightpanda/browser:nightly
```

**Build from Source:**
See the [Lightpanda GitHub repository](https://github.com/lightpanda-io/browser) for build instructions.

### Verifying Installation

Once installed, verify Lightpanda is working:
```bash
lightpanda --version
```

Tidewave will automatically detect and start Lightpanda on port 9222 when available. The `browser_inspect` tool will only appear in the available tools list when Lightpanda is running.

### Usage

With Lightpanda installed, you have access to three browser testing tools:

1. **`smoke_test`** - Server-side LiveView mount testing (always available)
2. **`eval_with_logs`** - Code evaluation with scoped log capture (always available)
3. **`browser_inspect`** - Full browser testing with JavaScript execution (requires Lightpanda)

Use them in sequence:
1. First run `smoke_test` to verify the page mounts without errors
2. Then use `browser_inspect` to verify JavaScript hooks and client-side behavior
