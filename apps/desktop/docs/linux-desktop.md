# Linux desktop build (downstream port)

Upstream publishes the desktop shell for macOS and Windows only; `apps/desktop`
treats Linux as an unsupported release target even though `scripts/primary-runtime/lock.json`,
the Electron shell and the POSIX launch scripts already carry Linux support. This fork keeps a
small, rebasable patch set that adds a local-only Linux build.

## Branches

| Branch | Meaning |
| --- | --- |
| `master` | Mirror of `deepseek-ai/deepseek-harness`. Never commit here. |
| `linux` | Default branch: the Linux port plus its patch series. Releases are tagged here. |

Because `master` equals upstream, `git diff master linux` is the complete port.

## Prerequisites

- Node.js >= 24.9 and the pnpm version from `packageManager` (`corepack enable`).
- Network access to `nodejs.org`, GitHub releases and the npm registry. Behind a proxy, set
  `HTTP(S)_PROXY` **and** `NODE_USE_ENV_PROXY=1`: the runtime download uses Node's built-in fetch,
  which ignores proxy variables by itself.
- `libfuse2t64` (Ubuntu 24.04+) only to run the AppImage; the unpacked directory needs no FUSE.
- `tar`, `python3`, and a working C++ toolchain for native workspace postinstalls.

## Build

```bash
pnpm install
pnpm --filter @deepseek-ai/dsh-desktop run check:package -- linux-x64   # environment preflight
pnpm run package:desktop:linux:x64:unsigned                             # AppImage + linux-unpacked
```

Artifacts land in `apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`.
`package:desktop:linux:x64:dir` stops at the unpacked directory.

Release settings live in the gitignored `apps/desktop/.env.linux`; `.env.linux.example` is the
template. Unlike the macOS and Windows targets there is no signing, notarization, mandatory-update
policy or upload flow: a Linux build is local-only and never writes a release record.

## Patch ledger

Every deviation from upstream, and what lets us delete it.

| Area | Files | Upstream reference | Keep? |
| --- | --- | --- | --- |
| Target admission, Linux env, no-signing flow, executable/desktop naming, upload-flow type narrowing | `scripts/desktop-build-paths.*`, `package-target.ts`, `desktop-package-environment.*`, `electron-builder-config.mjs`, `smoke-packaged-runtime.ts`, `prepare-runtime.ts`, `prepare-cli.ts`, `desktop-toolchain-preflight.ts`, `development-project.ts`, `desktop-edgeone.ts`, `desktop-upload-plan.ts`, `retain-desktop-ci.ts`, `upload-target.ts`, both `package.json` files, `.gitignore` | upstream README: "Linux is not a supported Desktop release target" | Yes, the core port |
| WASM sharp engine | `prepare-dsh.ts` (`runtime:sharp-wasm`), `package.json` devDependencies | [electron/electron#46323](https://github.com/electron/electron/issues/46323), [sharp install notes](https://sharp.pixelplumbing.com/install#electron-and-linux) | Until upstream ships its Linux engine choice |
| ASAR null vs undefined engine probe | `packages/document/office-kit/src/locate.ts`, `runtime-patch-policy.ts`, `patches/desktop-libreoffice-kit-asar.patch` | Electron ASAR returns `null` from `lstatSync` for missing entries | Until upstream fixes the probe |
| `desktop-linux` platform header | `packages/credentials/deepseek-account/src/client-metadata.ts` and `src/index.ts`, `apps/desktop/src/{main,platform-view,mandatory-update-policy}.ts` | — | Yes |

Why the sharp engine is replaced: the prebuilt `@img/sharp-linux-x64` exports its statically linked
glib symbols, which collide with the system glib that Electron loads into the global symbol scope.
Encodes happen to pass; every decode segfaults under `ELECTRON_RUN_AS_NODE`. The WebAssembly engine
carries no ELF symbols. `prepare-dsh.ts` removes the native copies, installs
`@img/sharp-wasm32` + `@emnapi/runtime` + `tslib`, and shadows the absent native names with a
throwing stub so resolution can never walk up to a host installation outside the packaged tree.

## Syncing upstream

Track upstream releases, not `master`: the desktop shell is released as one unit with a matching
`@deepseek-ai/dsh` version.

```bash
git fetch upstream --tags
git switch linux
git rebase upstream/master        # or the release tag being adopted
pnpm install                      # a pnpm-lock.yaml conflict is resolved by regenerating
pnpm --filter @deepseek-ai/dsh-desktop run check:package -- linux-x64
pnpm run package:desktop:linux:x64:unsigned
git tag -a linux-v<upstream-version>-<revision> -m "Linux desktop build for <upstream-version>"
git push origin linux --tags
```

`scripts/sync-upstream.sh` runs the fetch/rebase and prints the remaining steps.

Conflict hotspots, in order: `pnpm-lock.yaml` (regenerate), `package-target.ts`, `prepare-dsh.ts`,
`electron-builder-config.mjs`. Everything else is additive and merges cleanly. When an entry in the
patch ledger is fixed upstream, delete the corresponding commit with
`git rebase --onto <commit>^ <commit> linux` and re-run the build to confirm.

## Known limitations

- Unsigned local builds; there is no auto-update channel or installer integration.
- Office conversion and image processing use the WebAssembly engines, which are slower than the
  native ones but functional (the packaged smoke converts DOCX/XLSX/PPTX and renders PDFs).
- The AppImage needs `libfuse2t64`; use `--appimage-extract-and-run` or the unpacked directory
  otherwise.
- The desktop shell shares `$DSH_HOME` with the CLI, but owns `profiles/desktop` exclusively.
