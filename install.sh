#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# TOPRAK AI — One Click Installer
# GitHub: https://github.com/toprakt7777-dev/TOPRAK-AI
#
# NO ROOT REQUIRED
# ============================================================

set -u
set -o pipefail

# -----------------------------
# Configuration
# -----------------------------

REPO="toprakt7777-dev/TOPRAK-AI"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

DATA_DIR="/storage/emulated/0/ToprakAI"

MODEL_DIR="$DATA_DIR/models"
CHAT_DIR="$DATA_DIR/chats"
PROJECT_DIR="$DATA_DIR/projects"
TOOLS_DIR="$DATA_DIR/tools"
LOG_DIR="$DATA_DIR/logs"

MODEL="$MODEL_DIR/qwen3.5-4b-instruct-Q4_K_M.gguf"

MODEL_URL="https://huggingface.co/openresearchtools/Qwen3.5-4B-Instruct-GGUF/resolve/main/qwen3.5-4b-instruct-Q4_K_M.gguf"

MODEL_SHA256="2e3c607324e016a3f59bced47a5fa411330f1a252d18ad0237caded161f12b45"

LLAMA_DIR="$HOME/llama.cpp"
LLAMA_BUILD="$LLAMA_DIR/build-vulkan"
LLAMA_SERVER="$LLAMA_BUILD/bin/llama-server"
LLAMA_CLI="$LLAMA_BUILD/bin/llama-cli"

SERVER_SCRIPT="$DATA_DIR/start-server.sh"
UI_SCRIPT="$DATA_DIR/start-ui.sh"
LAUNCHER="$PREFIX/bin/toprak-ai"

LOG_FILE="$LOG_DIR/install.log"

# -----------------------------
# Colors
# -----------------------------

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

info() {
    echo -e "${CYAN}[INFO]${RESET} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${RESET} $*"
}

warning() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*"
}

step() {
    echo
    echo -e "${MAGENTA}============================================================${RESET}"
    echo -e "${WHITE}$*${RESET}"
    echo -e "${MAGENTA}============================================================${RESET}"
}

fail() {
    error "$*"
    error "Installation stopped."
    error "Log: $LOG_FILE"
    exit 1
}

# -----------------------------
# Header
# -----------------------------

clear 2>/dev/null || true

echo
echo -e "${MAGENTA}████████╗ ██████╗ ██████╗ ██████╗  █████╗ ██╗  ██╗${RESET}"
echo -e "${MAGENTA}╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔══██╗██║${RESET}"
echo -e "${MAGENTA}   ██║   ██║   ██║██████╔╝██████╔╝███████║██║${RESET}"
echo -e "${MAGENTA}   ██║   ██║   ██║██╔═══╝ ██╔═══╝ ██╔══██║██║${RESET}"
echo -e "${MAGENTA}   ██║   ╚██████╔╝██║     ██║     ██║  ██║███████╗${RESET}"
echo -e "${MAGENTA}   ╚═╝    ╚═════╝ ╚═╝     ╚═╝     ╚═╝  ╚═╝╚══════╝${RESET}"
echo
echo -e "${CYAN}                 TOPRAK AI INSTALLER${RESET}"
echo -e "${WHITE}                    Android / Termux${RESET}"
echo

# -----------------------------
# Check Termux
# -----------------------------

step "Checking environment"

if [ -z "${PREFIX:-}" ]; then
    fail "Termux environment was not detected."
fi

if [ ! -d "$PREFIX" ]; then
    fail "Invalid Termux PREFIX."
fi

ARCH="$(uname -m)"

info "Architecture: $ARCH"

if [ "$ARCH" != "aarch64" ]; then
    warning "This installer was designed primarily for ARM64/aarch64."
fi

success "Termux detected."

# -----------------------------
# Storage
# -----------------------------

step "Preparing shared storage"

if [ ! -d "/storage/emulated/0" ]; then
    fail "Android shared storage is not accessible."
fi

mkdir -p "$DATA_DIR" \
         "$MODEL_DIR" \
         "$CHAT_DIR" \
         "$PROJECT_DIR" \
         "$TOOLS_DIR" \
         "$LOG_DIR" || fail "Could not create ToprakAI directories."

# Start logging
touch "$LOG_FILE" 2>/dev/null || fail "Cannot write to $LOG_FILE."

exec > >(tee -a "$LOG_FILE") 2>&1

success "Shared storage available."
info "Project directory:"
echo "$DATA_DIR"

# -----------------------------
# Packages
# -----------------------------

step "Installing Termux dependencies"

pkg update -y || warning "pkg update returned an error."

PACKAGES="
git
python
wget
curl
clang
cmake
make
ninja
pkg-config
vulkan-tools
"

for PACKAGE in $PACKAGES; do
    if dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        success "$PACKAGE already installed."
    else
        info "Installing $PACKAGE..."
        pkg install -y "$PACKAGE" || fail "Failed to install $PACKAGE."
        success "$PACKAGE installed."
    fi
done

# -----------------------------
# Storage permission check
# -----------------------------

step "Checking Android storage permission"

TEST_FILE="$DATA_DIR/.write_test"

if ! touch "$TEST_FILE" 2>/dev/null; then
    warning "Storage permission is missing."

    echo
    echo "Run:"
    echo
    echo "  termux-setup-storage"
    echo
    echo "Allow the Android permission, then run the installer again."
    echo

    fail "Cannot write to shared storage."
fi

rm -f "$TEST_FILE"

success "Storage permission works."

# -----------------------------
# Free space
# -----------------------------

step "Checking free storage"

FREE_GB="$(df -Pk /storage/emulated/0 | awk 'NR==2 {printf "%.1f", $4/1024/1024}')"

info "Free storage: ${FREE_GB} GB"

# -----------------------------
# Vulkan
# -----------------------------

step "Checking Vulkan / Adreno"

if ! command -v vulkaninfo >/dev/null 2>&1; then
    fail "vulkaninfo is not available."
fi

VULKAN_OUTPUT="$(vulkaninfo --summary 2>&1 || true)"

echo "$VULKAN_OUTPUT"

if echo "$VULKAN_OUTPUT" | grep -qi "Turnip"; then
    success "Turnip Vulkan GPU detected."
else
    warning "Turnip was not detected in vulkaninfo output."
fi

ICD="$(find "$PREFIX" -type f \
    \( -name '*freedreno*.json' -o -name '*turnip*.json' \) \
    2>/dev/null | head -1)"

if [ -n "$ICD" ]; then
    success "Vulkan ICD:"
    echo "$ICD"
else
    warning "Could not automatically locate Turnip/Freedreno ICD."
fi

# -----------------------------
# llama.cpp
# -----------------------------

step "Preparing llama.cpp"

if [ ! -d "$LLAMA_DIR/.git" ]; then

    info "Cloning llama.cpp..."

    git clone \
        --depth 1 \
        https://github.com/ggml-org/llama.cpp.git \
        "$LLAMA_DIR" \
        || fail "Failed to clone llama.cpp."

    success "llama.cpp cloned."

else

    info "Updating existing llama.cpp..."

    cd "$LLAMA_DIR" || fail "Cannot enter llama.cpp."

    OLD_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

    if git pull --ff-only; then
        success "llama.cpp updated."
    else
        warning "Could not update llama.cpp. Using existing version."
    fi

    NEW_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

    if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
        info "llama.cpp source changed. Rebuild will be performed."
        rm -f "$LLAMA_BUILD/.toprakai-built-commit"
    fi
fi

cd "$LLAMA_DIR" || fail "Cannot enter llama.cpp."

CURRENT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# -----------------------------
# Build llama.cpp
# -----------------------------

step "Building llama.cpp with Vulkan"

NEED_BUILD=0

if [ ! -x "$LLAMA_SERVER" ]; then
    NEED_BUILD=1
fi

if [ ! -x "$LLAMA_CLI" ]; then
    NEED_BUILD=1
fi

if [ ! -f "$LLAMA_BUILD/.toprakai-built-commit" ]; then
    NEED_BUILD=1
fi

if [ "$NEED_BUILD" -eq 1 ]; then

    info "Configuring Vulkan build..."

    cmake \
        -B "$LLAMA_BUILD" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_VULKAN=ON \
        || fail "llama.cpp Vulkan configuration failed."

    info "Compiling llama.cpp..."

    cmake \
        --build "$LLAMA_BUILD" \
        -j4 \
        --target llama-cli llama-server \
        || fail "llama.cpp compilation failed."

    echo "$CURRENT_COMMIT" > "$LLAMA_BUILD/.toprakai-built-commit"

    success "llama.cpp Vulkan build completed."

else

    success "Existing llama.cpp Vulkan binaries are ready."

fi

if [ ! -x "$LLAMA_SERVER" ]; then
    fail "llama-server was not found after build."
fi

if [ ! -x "$LLAMA_CLI" ]; then
    fail "llama-cli was not found after build."
fi

success "llama-server OK."
success "llama-cli OK."

# -----------------------------
# Model
# -----------------------------

step "Preparing Qwen model"

MODEL_OK=0

if [ -f "$MODEL" ]; then

    info "Existing model found."

    SIZE_BYTES="$(wc -c < "$MODEL" 2>/dev/null || echo 0)"

    if [ "$SIZE_BYTES" -gt 2000000000 ]; then

        info "Checking SHA-256..."

        ACTUAL_SHA="$(sha256sum "$MODEL" | awk '{print $1}')"

        if [ "$ACTUAL_SHA" = "$MODEL_SHA256" ]; then
            success "Existing model passed SHA-256 verification."
            MODEL_OK=1
        else
            warning "Existing model SHA-256 is incorrect."
            warning "The model will be downloaded again."
            rm -f "$MODEL"
        fi

    else

        warning "Existing model is too small."
        rm -f "$MODEL"

    fi
fi

if [ "$MODEL_OK" -eq 0 ]; then

    info "Downloading Qwen 3.5 4B Instruct Q4_K_M..."
    info "This is approximately 2.7 GB."

    TEMP_MODEL="$MODEL.part"

    if command -v curl >/dev/null 2>&1; then

        curl \
            -L \
            --fail \
            --retry 5 \
            --retry-delay 3 \
            --continue-at - \
            -o "$TEMP_MODEL" \
            "$MODEL_URL" \
            || fail "Model download failed."

    else

        wget \
            -c \
            --tries=5 \
            -O "$TEMP_MODEL" \
            "$MODEL_URL" \
            || fail "Model download failed."

    fi

    if [ ! -f "$TEMP_MODEL" ]; then
        fail "Downloaded model file does not exist."
    fi

    info "Verifying downloaded model..."

    ACTUAL_SHA="$(sha256sum "$TEMP_MODEL" | awk '{print $1}')"

    if [ "$ACTUAL_SHA" != "$MODEL_SHA256" ]; then
        error "SHA-256 verification FAILED."
        error "Expected: $MODEL_SHA256"
        error "Actual:   $ACTUAL_SHA"

        rm -f "$TEMP_MODEL"

        fail "Model verification failed."
    fi

    mv "$TEMP_MODEL" "$MODEL" \
        || fail "Could not move verified model into place."

    success "Model downloaded and verified."

fi

# -----------------------------
# Compatibility test
# -----------------------------

step "Testing model + Vulkan"

if [ -n "$ICD" ]; then
    export VK_ICD_FILENAMES="$ICD"
fi

TEST_OUTPUT="$(
    "$LLAMA_CLI" \
        -m "$MODEL" \
        -ngl 99 \
        -c 512 \
        -n 8 \
        -p "Reply with exactly: TOPRAK AI READY" \
        2>&1
)" || true

echo "$TEST_OUTPUT"

if echo "$TEST_OUTPUT" | grep -qi "TOPRAK"; then
    success "Model inference test completed."
else
    warning "The inference test did not return the expected phrase."
    warning "The model/server may still work normally."
fi

# -----------------------------
# Download UI
# -----------------------------

step "Installing TOPRAK AI interface"

UI_FILE="$DATA_DIR/index.html"

info "Downloading index.html from GitHub..."

if curl \
    -L \
    --fail \
    --retry 5 \
    --retry-delay 2 \
    -o "$UI_FILE.tmp" \
    "$RAW/index.html"; then

    if [ -s "$UI_FILE.tmp" ]; then
        mv "$UI_FILE.tmp" "$UI_FILE"
        success "index.html installed."
    else
        rm -f "$UI_FILE.tmp"
        fail "Downloaded index.html is empty."
    fi

else

    rm -f "$UI_FILE.tmp"

    if [ -s "$UI_FILE" ]; then
        warning "Could not download new UI."
        warning "Existing index.html will be preserved."
    else
        fail "Could not download index.html."
    fi
fi

# -----------------------------
# Server launcher
# -----------------------------

step "Creating server launcher"

cat > "$SERVER_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

DATA_DIR="/storage/emulated/0/ToprakAI"

MODEL="$DATA_DIR/models/qwen3.5-4b-instruct-Q4_K_M.gguf"

LLAMA_SERVER="$HOME/llama.cpp/build-vulkan/bin/llama-server"

LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/server.log"

mkdir -p "$LOG_DIR"

if [ ! -f "$MODEL" ]; then
    echo "TOPRAK AI model not found:"
    echo "$MODEL"
    exit 1
fi

if [ ! -x "$LLAMA_SERVER" ]; then
    echo "llama-server not found:"
    echo "$LLAMA_SERVER"
    exit 1
fi

ICD="$(find "$PREFIX" -type f \
    \( -name '*freedreno*.json' -o -name '*turnip*.json' \) \
    2>/dev/null | head -1)"

if [ -n "$ICD" ]; then
    export VK_ICD_FILENAMES="$ICD"
fi

if curl -fsS --max-time 2 \
    http://127.0.0.1:8080/health >/dev/null 2>&1; then

    echo "TOPRAK AI server is already running."
    echo "http://127.0.0.1:8080"

    exit 0
fi

echo "Starting TOPRAK AI server..."

nohup "$LLAMA_SERVER" \
    -m "$MODEL" \
    --host 127.0.0.1 \
    --port 8080 \
    -c 2048 \
    -ngl 99 \
    >> "$LOG_FILE" 2>&1 &

sleep 2

if curl -fsS --max-time 3 \
    http://127.0.0.1:8080/health >/dev/null 2>&1; then

    echo
    echo "TOPRAK AI SERVER: ONLINE"
    echo "http://127.0.0.1:8080"
    echo
    echo "Log:"
    echo "$LOG_FILE"

else

    echo
    echo "Server may still be starting."
    echo "Check:"
    echo "$LOG_FILE"

fi
EOF

chmod 700 "$SERVER_SCRIPT" 2>/dev/null || true

success "Server launcher created."

# -----------------------------
# UI launcher
# -----------------------------

step "Creating UI launcher"

cat > "$UI_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

DATA_DIR="/storage/emulated/0/ToprakAI"

UI="$DATA_DIR/index.html"

LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/ui.log"

mkdir -p "$LOG_DIR"

if [ ! -f "$UI" ]; then
    echo "index.html not found:"
    echo "$UI"
    exit 1
fi

if curl -fsS --max-time 2 \
    http://127.0.0.1:3000/ >/dev/null 2>&1; then

    echo "TOPRAK AI UI is already running."
    echo
    echo "Open:"
    echo "http://127.0.0.1:3000"

    exit 0
fi

echo "Starting TOPRAK AI UI..."

cd "$DATA_DIR" || exit 1

nohup python -m http.server \
    3000 \
    --bind 127.0.0.1 \
    >> "$LOG_FILE" 2>&1 &

sleep 1

echo
echo "TOPRAK AI UI:"
echo "http://127.0.0.1:3000"
echo
echo "Open that address in your browser."
echo
echo "Log:"
echo "$LOG_FILE"
EOF

chmod 700 "$UI_SCRIPT" 2>/dev/null || true

success "UI launcher created."

# -----------------------------
# Main launcher
# -----------------------------

step "Creating TOPRAK AI command"

cat > "$LAUNCHER" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

DATA_DIR="/storage/emulated/0/ToprakAI"

while true; do

    clear

    echo
    echo "======================================"
    echo "          TOPRAK AI"
    echo "======================================"
    echo
    echo "1. Start AI Server"
    echo "2. Start Web UI"
    echo "3. Start EVERYTHING"
    echo "4. Check Server"
    echo "5. Open Project Folder"
    echo "6. Show Logs"
    echo "7. Exit"
    echo
    printf "Choose: "

    read -r CHOICE

    case "$CHOICE" in

        1)
            bash "$DATA_DIR/start-server.sh"
            echo
            read -r -p "Press Enter..."
            ;;

        2)
            bash "$DATA_DIR/start-ui.sh"
            echo
            read -r -p "Press Enter..."
            ;;

        3)
            bash "$DATA_DIR/start-server.sh"
            echo
            bash "$DATA_DIR/start-ui.sh"
            echo
            echo "Open in your browser:"
            echo "http://127.0.0.1:3000"
            echo
            read -r -p "Press Enter..."
            ;;

        4)
            echo
            if curl -fsS --max-time 3 \
                http://127.0.0.1:8080/health >/dev/null 2>&1; then

                echo "SERVER: ONLINE"

            else

                echo "SERVER: OFFLINE"

            fi

            echo
            read -r -p "Press Enter..."
            ;;

        5)
            echo
            echo "Project:"
            echo "$DATA_DIR"
            echo
            ;;

        6)
            echo
            echo "Server log:"
            echo "$DATA_DIR/logs/server.log"
            echo
            echo "UI log:"
            echo "$DATA_DIR/logs/ui.log"
            echo
            echo "Installer log:"
            echo "$DATA_DIR/logs/install.log"
            echo
            read -r -p "Press Enter..."
            ;;

        7)
            exit 0
            ;;

        *)
            echo
            echo "Invalid option."
            sleep 1
            ;;

    esac

done
EOF

chmod 700 "$LAUNCHER"

success "toprak-ai command created."

# -----------------------------
# Save installer copy
# -----------------------------

step "Saving installer"

INSTALL_COPY="$DATA_DIR/install.sh"

if [ -f "$0" ] && [ "$0" != "bash" ] && [ -r "$0" ]; then
    cp "$0" "$INSTALL_COPY" 2>/dev/null || true
fi

# If executed through curl | bash, download the canonical copy.
if [ ! -s "$INSTALL_COPY" ]; then

    curl \
        -L \
        --fail \
        --retry 3 \
        -o "$INSTALL_COPY.tmp" \
        "$RAW/install.sh" \
        2>/dev/null || true

    if [ -s "$INSTALL_COPY.tmp" ]; then
        mv "$INSTALL_COPY.tmp" "$INSTALL_COPY"
    else
        rm -f "$INSTALL_COPY.tmp"
    fi
fi

if [ -s "$INSTALL_COPY" ]; then
    success "Installer saved:"
    echo "$INSTALL_COPY"
else
    warning "Could not save local installer copy."
fi

# -----------------------------
# Final verification
# -----------------------------

step "Final verification"

[ -x "$LLAMA_SERVER" ] && success "llama-server: OK" \
    || warning "llama-server: FAILED"

[ -x "$LLAMA_CLI" ] && success "llama-cli: OK" \
    || warning "llama-cli: FAILED"

[ -f "$MODEL" ] && success "Qwen model: OK" \
    || warning "Qwen model: FAILED"

[ -s "$UI_FILE" ] && success "Web UI: OK" \
    || warning "Web UI: FAILED"

[ -x "$SERVER_SCRIPT" ] && success "Server launcher: OK" \
    || warning "Server launcher: FAILED"

[ -x "$UI_SCRIPT" ] && success "UI launcher: OK" \
    || warning "UI launcher: FAILED"

[ -x "$LAUNCHER" ] && success "toprak-ai command: OK" \
    || warning "toprak-ai command: FAILED"

# -----------------------------
# Finish
# -----------------------------

echo
echo -e "${GREEN}============================================================${RESET}"
echo -e "${GREEN}              TOPRAK AI INSTALLATION DONE${RESET}"
echo -e "${GREEN}============================================================${RESET}"
echo

echo "Project:"
echo "$DATA_DIR"
echo

echo "Model:"
echo "$MODEL"
echo

echo "Server:"
echo "$SERVER_SCRIPT"
echo

echo "UI:"
echo "$UI_SCRIPT"
echo

echo "Logs:"
echo "$LOG_DIR"
echo

echo "Launch:"
echo
echo "  toprak-ai"
echo

echo "Or start everything directly:"
echo
echo "  bash $SERVER_SCRIPT"
echo "  bash $UI_SCRIPT"
echo

echo "Web UI:"
echo
echo "  http://127.0.0.1:3000"
echo

echo -e "${GREEN}TOPRAK AI IS READY 🔥${RESET}"
echo
