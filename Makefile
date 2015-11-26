COMPONENT=GroupProjectAppC
CFLAGS+=-DDATARATE=50 -DMSG_POOL_SIZE=158 -DSINK_ADDRESS=1 -DCC2420_NO_ACKNOWLEDGEMENTS
CFLAGS += -I$(TOSDIR)/lib/printf -DNEW_PRINTF_SEMANTICS -Ddebug_printf
BUILD_DEPS+=flocklab_embedded_image
SENSORBOARD=flocklab
PFLAGS+=-board=$(SENSORBOARD) -I../../tos/sensorboards/$(SENSORBOARD)
include $(MAKERULES)

flocklab_embedded_image: exe
	@sed -i -n '1h;1!H;$${ g;s/<data>.*<\/data>/<data>#'"`base64 $(MAIN_EXE) | tr '\n' '#' | sed 's/\//\\\\\//g'`"'<\/data>/;s/#/\n/g;p}' flocklab.xml
