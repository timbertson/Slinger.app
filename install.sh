#!/usr/bin/env bash
set -eux
gup -u net.gfxmonk.slinger.agent.plist
ln -sfn "$(pwd)/net.gfxmonk.slinger.agent.plist" ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/net.gfxmonk.slinger.agent.plist || true
launchctl load ~/Library/LaunchAgents/net.gfxmonk.slinger.agent.plist || true
launchctl stop ~/Library/LaunchAgents/net.gfxmonk.slinger.agent.plist || true
launchctl start ~/Library/LaunchAgents/net.gfxmonk.slinger.agent.plist
