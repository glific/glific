# .profile.d/002_ssh_profile_setup.sh
cp /app/.profile.d/000_apt.sh /etc/profile.d/ || true
cp /app/.profile.d/001_fixup_ssh.sh /etc/profile.d || true

