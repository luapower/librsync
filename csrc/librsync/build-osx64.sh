[ `uname` = Linux ] && export X=x86_64-apple-darwin11-
P=osx64 C="-arch x86_64 -DSIZEOF_LONG=8 -DSIZEOF_UNSIGNED_LONG=8 -DSIZEOF_SIZE_T=8" \
	L="-arch x86_64 -install_name @rpath/librsync.dylib" \
	D=librsync.dylib A=librsync.a ./build.sh
