function tf = local_isdryrun()
% True when MEXITK_REFCAP_DRYRUN is set to anything other than '0'.
v = getenv('MEXITK_REFCAP_DRYRUN');
tf = ~isempty(v) && ~strcmp(v, '0');
end
