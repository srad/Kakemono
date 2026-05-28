#!/bin/bash
set -e

echo "=== Erlang/Elixir Setup for Kakemono ==="
echo "Target: Erlang 27.3.4.8, Elixir 1.18.2-otp-27"
echo ""

# Remove existing system Erlang/Elixir
echo ">>> Removing existing system Erlang/Elixir packages..."
sudo apt remove -y erlang* elixir* 2>/dev/null || true
sudo apt autoremove -y

# Install build dependencies
echo ""
echo ">>> Installing build dependencies..."
sudo apt update
sudo apt install -y \
  build-essential \
  autoconf \
  m4 \
  libncurses5-dev \
  libncurses-dev \
  libwxgtk3.2-dev \
  libwxgtk-webview3.2-dev \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  libpng-dev \
  libssh-dev \
  unixodbc-dev \
  xsltproc \
  fop \
  libxml2-utils \
  openjdk-11-jdk \
  curl \
  git

# Install asdf if not present
if [ ! -d "$HOME/.asdf" ]; then
  echo ""
  echo ">>> Installing asdf..."
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
fi

# Source asdf
export ASDF_DIR="$HOME/.asdf"
. "$HOME/.asdf/asdf.sh"

# Add to bashrc if not already there
if ! grep -q 'asdf.sh' ~/.bashrc; then
  echo ""
  echo ">>> Adding asdf to ~/.bashrc..."
  echo '' >> ~/.bashrc
  echo '# asdf version manager' >> ~/.bashrc
  echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
  echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
fi

# Add plugins
echo ""
echo ">>> Adding asdf plugins..."
asdf plugin add erlang 2>/dev/null || true
asdf plugin add elixir 2>/dev/null || true

# Install Erlang (this takes a while)
echo ""
echo ">>> Installing Erlang 27.3.4.8 (this will take 10-15 minutes)..."
asdf install erlang 27.3.4.8

# Install Elixir
echo ""
echo ">>> Installing Elixir 1.18.2-otp-27..."
asdf install elixir 1.18.2-otp-27

# Set versions for this project
echo ""
echo ">>> Setting local versions for Kakemono project..."
cd "$(dirname "$0")"
asdf local erlang 27.3.4.8
asdf local elixir 1.18.2-otp-27

# Clean and rebuild project
echo ""
echo ">>> Cleaning and rebuilding project..."
rm -rf _build deps
mix local.hex --force
mix local.rebar --force
mix deps.get
mix compile

echo ""
echo "=== Setup complete! ==="
echo "Run 'source ~/.bashrc' or open a new terminal, then 'mix phx.server'"
