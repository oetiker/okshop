#!/bin/sh
set -e
V=$(cat VERSION)
T=okshop
echo $V $(date +"%Y-%m-%d %H:%M:%S %z") $(git config user.name) '<'$(git config user.email)'>' >> CHANGES.new
echo >> CHANGES.new
echo ' -' >> CHANGES.new
echo >> CHANGES.new
cat CHANGES >> CHANGES.new && mv CHANGES.new CHANGES
$EDITOR CHANGES
#./bootstrap
make dist
cat $T-$V.tar.gz | ssh oltcal@freddie 'tar zxf -;cd '$T'-'$V';./configure --prefix=$HOME/opt/'$T';make install;$HOME/start-okshop.sh'