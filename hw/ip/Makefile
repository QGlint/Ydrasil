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

# 在 USE_BENDER=0 时，退化为通过 Bender.yml 手动解析清单（含 dependencies.path 递归）
manifest_of = $(firstword $(wildcard $(1)/Bender.yml $(1)/Bender.yaml))

manifest_dep_paths = $(strip $(shell awk '/^[[:space:]]*path:[[:space:]]*/{v=$$2; gsub(/["\047]/, "", v); print v}' $(call manifest_of,$(1))))

manifest_dirs = $(1) $(foreach p,$(call manifest_dep_paths,$(1)),$(call manifest_dirs,$(abspath $(1)/$(p))))

manifest_files_rel = $(strip $(shell awk '/^[[:space:]]*files:[[:space:]]*$$/{in_files=1;next} in_files&&/^[[:space:]]*-[[:space:]]+/{line=$$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line); gsub(/[[:space:]]+#.*$$/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$$/,"",line); gsub(/["\047]/,"",line); print line; next} in_files&&!/^[[:space:]]*-[[:space:]]+/{in_files=0}' $(call manifest_of,$(1))))

manifest_files_abs = $(foreach f,$(call manifest_files_rel,$(1)),$(abspath $(1)/$(f)))

manifest_incdirs_rel = $(strip $(shell awk '/^[[:space:]]*include_dirs:[[:space:]]*$$/{in_inc=1;next} in_inc&&/^[[:space:]]*-[[:space:]]+/{line=$$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line); gsub(/[[:space:]]+#.*$$/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$$/,"",line); gsub(/["\047]/,"",line); print line; next} in_inc&&!/^[[:space:]]*-[[:space:]]+/{in_inc=0}' $(call manifest_of,$(1))))

manifest_incdirs_abs = $(foreach d,$(call manifest_incdirs_rel,$(1)),$(abspath $(1)/$(d)))

manifest_files_for_ip = $(sort $(foreach d,$(call manifest_dirs,$(1)),$(call manifest_files_abs,$(d))))
manifest_incdirs_for_ip = $(sort $(foreach d,$(call manifest_dirs,$(1)),$(call manifest_incdirs_abs,$(d))))

define assert_manifest_and_files
$(if $(call manifest_of,$(1)),,$(error Missing Bender.yml/Bender.yaml in $(1)))
$(foreach f,$(2),$(if $(wildcard $(f)),,$(error Missing file listed in Bender manifest: $(f))))
endef

define assert_incdirs
$(foreach d,$(1),$(if $(wildcard $(d)),$(if $(wildcard $(d)/.),,$(error Include path is not a directory: $(d))),$(error Missing include directory listed in Bender manifest: $(d))))
endef


$(foreach ip,$(ALL_IPS), \
  $(eval _ip_dir := $(IP_ROOT)/$(ip)) \
  $(eval _ip_files := $(call manifest_files_for_ip,$(_ip_dir))) \
  $(eval _ip_incdirs := $(call manifest_incdirs_for_ip,$(_ip_dir))) \
  $(call assert_manifest_and_files,$(_ip_dir),$(_ip_files)) \
  $(call assert_incdirs,$(_ip_incdirs)) \
  $(eval RTL_SRCS += $(_ip_files)) \
  $(eval INC_DIRS += $(_ip_incdirs)) \
)

INC_DIRS += $(sort $(dir $(RTL_SRCS)))

export RTL_SRCS INC_DIRS ALL_IPS
