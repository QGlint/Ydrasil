IP_ROOT := $(PROJECT_ROOT)/hw/ip
export IP_ROOT

##################################
# IP List (No deps resolver)
##################################

ALL_IPS := $(strip $(IP))
$(foreach ip,$(ALL_IPS),$(info >>> PROCESSING: $(ip)))

##################################
# Collect
##################################

RTL_SRCS :=
INC_DIRS :=



$(foreach ip,$(ALL_IPS), \
  $(eval RTL_SRCS += $(IP_ROOT)/$(ip)/rtl/*.sv) \
  $(eval INC_DIRS += $(IP_ROOT)/$(ip)/rtl) \
  $(eval INC_DIRS += $(IP_ROOT)/$(ip)/include) \
)

export RTL_SRCS INC_DIRS ALL_IPS
