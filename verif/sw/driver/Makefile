SHELL := /bin/sh

ROOT := $(abspath ../../..)
DRIVER_DIR := $(ROOT)/sw/app/driver
BUILD_DIR ?= $(ROOT)/build/verif/sw/driver
TARGET := $(BUILD_DIR)/driver_sim
CC ?= cc
CFLAGS ?= -O2 -g -std=c11 -Wall -Wextra -Werror

SOURCES := \
	driver_sim.c \
	mock_monitor_bus.c \
	$(DRIVER_DIR)/lm75b.c \
	$(DRIVER_DIR)/atk_ms601m.c \
	$(DRIVER_DIR)/font_small.c \
	$(DRIVER_DIR)/ssd1306.c

.PHONY: all test clean

all: $(TARGET)

$(TARGET): $(SOURCES) $(wildcard *.h) $(wildcard $(DRIVER_DIR)/*.h)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(CFLAGS) -I. -I"$(DRIVER_DIR)" $(SOURCES) -o "$@"

test: $(TARGET)
	"$(TARGET)"

clean:
	rm -rf "$(BUILD_DIR)"
