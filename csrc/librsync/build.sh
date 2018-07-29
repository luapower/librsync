${X}gcc -c -O2 $C *.c -I. -I../blake2
${X}gcc *.o -shared -o ../../bin/$P/$D $L \
	-L../../bin/$P -lblake2
rm -f      ../../bin/$P/$A
${X}ar rcs ../../bin/$P/$A *.o
rm *.o
