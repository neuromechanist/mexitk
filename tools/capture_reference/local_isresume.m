function tf = local_isresume()
% True when MEXITK_REFCAP_RESUME is set to anything other than '0'.
v = getenv('MEXITK_REFCAP_RESUME');
tf = ~isempty(v) && ~strcmp(v, '0');
end
