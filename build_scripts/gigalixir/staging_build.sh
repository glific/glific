echo "Checking out to master"
git checkout master

echo "Rebase with origin"
git fetch origin

echo "Switching to tag"
git checkout -b tag_$1 $1

echo "fetching data from gigalixir"
git pull staging master

echo "pushing data to staging server"
git push staging tag_$1:master

# echo "SSH to portal"
echo "clean SSH server for Staging"
gigalixir ps:ssh -a glific-staging < ./build_scripts/ssh_profile.sh
