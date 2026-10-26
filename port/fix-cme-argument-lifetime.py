from pathlib import Path

root = Path('/tmp/ruby-filc/ruby-4.0.7-glibc')
paths = {name: root / name for name in ('vm_insnhelper.c', 'vm_insnhelper.h', 'vm_args.c')}
texts = {name: path.read_text() for name, path in paths.items()}

def replace(text, old, new, count=1):
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f'Expected {count} occurrences, got {actual}: {old!r}')
    return text.replace(old, new)

def section(text, name, transform):
    start = text.index('\n' + name + '(')
    end = text.index('\nstatic ', start)
    return text[:start] + transform(text[start:end]) + text[end:]

text = texts['vm_insnhelper.c']
text = replace(text,
    'static inline VALUE vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc, int param_size, int local_size);',
    'static inline VALUE vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *cme, int opt_pc, int param_size, int local_size);')
text = replace(text,
    'vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc)',
    'vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me, int opt_pc)', 2)
text = replace(text,
    'vm_call_iseq_setup_tailcall(ec, cfp, calling, 0)',
    'vm_call_iseq_setup_tailcall(ec, cfp, calling, vm_cc_cme(calling->cc), 0)')
text = section(text, 'vm_call_iseq_setup_tailcall_opt_start', lambda value: replace(value,
    'vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc)',
    'vm_call_iseq_setup_tailcall(ec, cfp, calling, vm_cc_cme(cc), opt_pc)'))

def update_arg_setup(value):
    value = replace(value, 'const rb_iseq_t *iseq, VALUE *argv',
                    'const rb_iseq_t *iseq, const rb_callable_method_entry_t *cme, VALUE *argv')
    value = replace(value, 'vm_cc_cme(cc)', 'cme', 6)
    value = replace(value, 'vm_call_cacheable(ci, cc)', 'vm_call_cacheable(ci, cc, cme)', 4)
    value = replace(value, 'vm_call_iseq_optimizable_p(ci, cc)', 'vm_call_iseq_optimizable_p(ci, cc, cme)')
    return replace(value, 'setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_method)',
                   'setup_parameters_complex(ec, iseq, calling, cme, ci, argv, arg_setup_method)')
text = section(text, 'vm_callee_setup_arg', update_arg_setup)

def update_iseq_setup(value):
    value = replace(value,
        '    const struct rb_callcache *cc = calling->cc;\n    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);',
        '    const rb_callable_method_entry_t *cme = vm_cc_cme(calling->cc);\n    const rb_iseq_t *iseq = def_iseq_ptr(cme->def);')
    value = replace(value, 'vm_callee_setup_arg(ec, calling, iseq, cfp->sp',
                    'vm_callee_setup_arg(ec, calling, iseq, cme, cfp->sp')
    return replace(value, 'vm_call_iseq_setup_2(ec, cfp, calling, opt_pc, param_size, local_size)',
                   'vm_call_iseq_setup_2(ec, cfp, calling, cme, opt_pc, param_size, local_size)')
for name in ('vm_call_iseq_setup', 'vm_call_iseq_fwd_setup'):
    text = section(text, name, update_iseq_setup)

def update_setup_2(value):
    value = replace(value, 'int opt_pc, int param_size, int local_size)',
                    'const rb_callable_method_entry_t *cme, int opt_pc, int param_size, int local_size)')
    value = replace(value, '    const struct rb_callcache *cc = calling->cc;\n', '')
    value = replace(value, 'vm_cc_cme(cc)', 'cme')
    return replace(value, 'vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc)',
                   'vm_call_iseq_setup_tailcall(ec, cfp, calling, cme, opt_pc)')
text = section(text, 'vm_call_iseq_setup_2', update_setup_2)

def update_tailcall(value):
    value = replace(value, '    const struct rb_callcache *cc = calling->cc;\n', '')
    return replace(value, '    const rb_callable_method_entry_t *me = vm_cc_cme(cc);\n', '')
text = section(text, 'vm_call_iseq_setup_tailcall', update_tailcall)
text = replace(text, 'setup_parameters_complex(ec, iseq, calling, calling->cd->ci, argv, arg_setup_method)',
               'setup_parameters_complex(ec, iseq, calling, cme, calling->cd->ci, argv, arg_setup_method)')
text = replace(text, 'setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_type)',
               'setup_parameters_complex(ec, iseq, calling, calling->cc ? vm_cc_cme(calling->cc) : NULL, ci, argv, arg_setup_type)')
texts['vm_insnhelper.c'] = text

text = texts['vm_insnhelper.h']
for name in ('vm_call_cacheable', 'vm_call_iseq_optimizable_p'):
    text = replace(text, name + '(const struct rb_callinfo *ci, const struct rb_callcache *cc)',
                   name + '(const struct rb_callinfo *ci, const struct rb_callcache *cc, const rb_callable_method_entry_t *cme)')
text = replace(text, 'return !(vm_ci_flag(ci) & VM_CALL_FORWARDING)',
               'return vm_cc_valid(cc) && !(vm_ci_flag(ci) & VM_CALL_FORWARDING)')
text = replace(text, 'METHOD_ENTRY_VISI(vm_cc_cme(cc))', 'METHOD_ENTRY_VISI(cme)')
text = replace(text, 'vm_call_cacheable(ci, cc)', 'vm_call_cacheable(ci, cc, cme)')
texts['vm_insnhelper.h'] = text

text = texts['vm_args.c']
text = replace(text, '                         struct rb_calling_info *const calling,\n                         const struct rb_callinfo *ci,',
               '                         struct rb_calling_info *const calling,\n                         const rb_callable_method_entry_t *cme,\n                         const struct rb_callinfo *ci,')
text = replace(text, '    const rb_callable_method_entry_t *cme = calling->cc ? vm_cc_cme(calling->cc) : NULL;\n', '')
texts['vm_args.c'] = text

for name, text in texts.items():
    paths[name].write_text(text)
