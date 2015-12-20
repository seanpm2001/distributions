#!/bin/bash

# globals
releases=../../releases

# init colors
txtnon='\e[0m'    # color reset
txtred='\e[0;31m' # Red
txtgrn='\e[0;32m' # Green
txtylw='\e[0;33m' # Yellow

function fail() {
	printf $txtred%s$txtnon\\n "$@"
	exit 1
}

function warn() {
	printf $txtylw%s$txtnon\\n "$@"
}

function notice() {
	printf $txtgrn%s$txtnon\\n "$@"
}

# dep checks
if [ ! -f `which jq` ]
then
	fail "must have 'jq' installed"
fi

function printDistInfo() {
	# print json output
	jq -e ".platforms[\"$goos\"]" dist.json > /dev/null
	if [ ! $? -eq 0 ]
	then
		cp dist.json dist.json.temp
		jq ".platforms[\"$goos\"] = {\"name\":\"$goos Binary\",\"archs\":{}}" dist.json.temp > dist.json
	fi

	local binname="ipfs"
	if [ "$goos" = "windows" ]
	then
		binname="ipfs.exe"
	fi

	cp dist.json dist.json.temp
	jq ".platforms[\"$goos\"].archs[\"$goarch\"] = {\"link\":\"$goos-$goarch/$binname\"}" dist.json.temp > dist.json

}

function doBuild() {
	local goos=$1
	local goarch=$2
	local target=$3
	local output=$4

	echo "==> building for $goos $goarch"

	dir=$output/$1-$2
	if [ -e $dir ]
	then
		echo "    $dir exists, skipping build"
		return
	fi
	echo "    output to $dir"
	mkdir -p $dir

	(cd $dir && GOOS=$goos GOARCH=$goarch go build $target 2> build-log)
	local success=$?
	if [ "$success" == 0 ]
	then
		notice "    success!"
		printDistInfo
	else
		warn "    failed."
	fi

	# output results to results table
	echo $target, $goos, $goarch, $success >> $output/results
}

function printInitialDistfile() {
	local distname=$1
	local version=$2
	printf "{\"id\":\"$distname\",\"version\":\"$version\",\"releaseLink\":\"releases/$distname/$version\"}" |
	jq ".name = \"go-ipfs\"" |
	jq ".platforms = {}" |
	jq ".description = \"`cat description`\""
}

function printBuildInfo() {
	# print out build information
	local commit=$1
	go version
	echo "git sha of code: $commit" 
	uname -a
	echo built on `date`
}

function buildWithMatrix() {
	local matfile=$1
	local gobin=$2
	local output=$3
	local commit=$4

	if [ -z "$output" ]; then
		fail "error: output dir not specified"
	fi

	if [ ! -e $matfile ]; then
		fail "build matrix $matfile does not exist"
	fi

	mkdir -p $output

	printInitialDistfile "go-ipfs" $version > dist.json
	printBuildInfo $commit > $output/build-info

	# build each os/arch combo
	while read line
	do
		doBuild $line $gobin $output
	done < $matfile

	mv dist.json $output/dist.json
}

function checkoutVersion() {
	local repopath=$1
	local ref=$2

	echo "==> checking out version $ref in $repopath"
	(cd $repopath && git checkout $ref > /dev/null)

	if [ "$?" != 0 ]
	then
		fail "failed to check out $ref in $repopath"
	fi
}

function currentSha() {
	(cd $1 && git show --pretty="%H")
}

function printVersions() {
	versarr=""
	while read v
	do
		versarr="$versarr $v"
	done < versions
	echo "building versions: $versarr"
}

function startGoBuilds() {
	distname=$1
	gpath=$2

	outputDir=$releases/$distname

	# if the output directory already exists, warn user
	if [ -e $outputDir ]
	then
		warn "dirty output directory"
		warn "will skip building already existing binaries"
	fi

	export GOPATH=$(pwd)/gopath
	if [ ! -e $GOPATH ]
	then
		echo "fetching ipfs code..."
		go get $gpath 2> /dev/null
	fi

	repopath=$GOPATH/src/$gpath

	printVersions

	echo ""
	while read version
	do
		notice "Building version $version binaries"
		checkoutVersion $repopath $version

		buildWithMatrix matrices/$version $gpath $outputDir/$version $(currentSha $repopath)
		echo ""
	done < versions

	notice "build complete!"
}
# globals


gpath=github.com/ipfs/go-ipfs/cmd/ipfs

startGoBuilds go-ipfs $gpath
