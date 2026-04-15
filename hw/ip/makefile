##################################
# Load Submodules
##################################

-include $(PROJECT_ROOT)/hw/ip/import/submodules.mk

IP_ROOT := $(PROJECT_ROOT)/hw/ip
export IP_ROOT
##################################
# Resolver
##################################

ALL_IPS :=
VISITED_IPS :=

define LOAD_IP
  # 检查是否访问过，注意这里为了安全建议也用 $(if) 代替 ifeq
  ifeq ($(filter $1,$(VISITED_IPS)),)
    VISITED_IPS += $1
    ALL_IPS += $1
    
    $(info >>> PROCESSING: $1)
    
    # 1. 包含依赖文件
    ifeq ($(filter $1,$(SUBMODULE_IPS)),)
      -include $(IP_ROOT)/$1/deps.mk
    else
      -include $(IP_ROOT)/submodules.mk
    endif

    # 2. 关键：使用 $$ 来延迟展开 $1_REQUIRED_IPS
    # 这样 eval 在处理这一行时，上面的 include 已经生效了
    $$(foreach d,$$(REQUIRED_IPS),$$(eval $$(call LOAD_IP,$$d)))
  endif
endef

$(foreach ip,$(IP),$(eval $(call LOAD_IP,$(ip))))

##################################
# Collect
##################################

RTL_SRCS :=
INC_DIRS :=



$(foreach ip,$(ALL_IPS), \
  $(if $(filter common_cells,$(ip)), \
    $(eval RTL_SRCS += $(COMMON_CELLS_SRCS)) \
    $(eval INC_DIRS += $(IP_ROOT)/$(ip)/include) \
    $(eval INC_DIRS += $($(ip)_RTL_DIR)), \
      $(if $(filter $(ip),$(SUBMODULE_IPS)), \
      $(eval RTL_SRCS += $($(ip)_RTL_DIR)/*.sv) \
      $(eval INC_DIRS += $(IP_ROOT)/$(ip)/include) \
      $(eval INC_DIRS += $($(ip)_RTL_DIR)), \
        $(eval RTL_SRCS += $(IP_ROOT)/$(ip)/rtl/*.sv) \
        $(eval INC_DIRS += $(IP_ROOT)/$(ip)/rtl) \
        $(eval INC_DIRS += $(IP_ROOT)/$(ip)/include) \
    ) \
  ) \
)

export RTL_SRCS INC_DIRS ALL_IPS
