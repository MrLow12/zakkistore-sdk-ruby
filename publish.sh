#!/bin/bash
# Script helper untuk mempublikasikan Ruby Gem Zakki Store SDK ke RubyGems
GEM_VERSION="1.0.3"
GEM_NAME="zakkistore-sdk"

echo "🛠️ Membangun paket gem..."
gem build zakkistore-sdk.gemspec

if [ $? -eq 0 ]; then
  echo "📤 Mengunggah gem ke RubyGems..."
  gem push "${GEM_NAME}-${GEM_VERSION}.gem"
else
  echo "❌ Gagal membangun gem."
  exit 1
fi
