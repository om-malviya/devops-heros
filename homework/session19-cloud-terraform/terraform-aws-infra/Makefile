# Session 19 - Terraform helper targets
# Usage: make init | make plan | make apply | make destroy
TF ?= terraform

.PHONY: init fmt validate plan apply output destroy clean

init:
	$(TF) init

fmt:
	$(TF) fmt -recursive

validate: fmt
	$(TF) validate

plan: validate
	$(TF) plan -out=tfplan

apply:
	$(TF) apply tfplan

output:
	$(TF) output

destroy:
	$(TF) destroy

clean:
	rm -rf .terraform tfplan
