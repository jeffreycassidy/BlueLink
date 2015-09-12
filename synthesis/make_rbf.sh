#
# Note: for CAPI, .rbf file should be ~33 MB
quartus_asm --read_settings_files=on --write_settings_files=off psl -c psl
quartus_cpf --configuration_mode=FPP --convert quartus_output/psl.sof psl.rbf
