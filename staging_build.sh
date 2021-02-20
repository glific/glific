echo "Checking out to master"
git checkout master

echo "Rebase with origin"
git fetch origin

echo "Switching to tag"
git checkout -b tag_$1 $1