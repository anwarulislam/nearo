# Finishing a Nearo chat

Before the final reply in each Nearo chat, run `scripts/dev.sh --build-only` from the repository root. This builds the macOS Debug app and verifies its signature.

On success, include a clickable absolute-path link to `.build/Build/Products/Debug/Nearo.app` in the final reply. If the build fails, report the error.
