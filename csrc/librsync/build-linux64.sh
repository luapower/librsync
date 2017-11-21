P=linux64 C="-fPIC -DSIZEOF_LONG=8 -DSIZEOF_UNSIGNED_LONG=8 -DSIZEOF_SIZE_T=8" \
	L="-s -static-libgcc" D=librsync.so A=librsync.a ./build.sh
