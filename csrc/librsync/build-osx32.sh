[ `uname` = Linux ] && export X=i386-apple-darwin11-
P=osx32 C="-arch i386 -DSIZEOF_LONG=4 -DSIZEOF_UNSIGNED_LONG=4 -DSIZEOF_SIZE_T=4" \
	L="-arch i386 -install_name @rpath/librsync.dylib" \
	D=librsync.dylib A=librsync.a ./build.sh
