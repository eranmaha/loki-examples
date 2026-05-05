import cf from 'cloudfront';
var kvsHandle = cf.kvs();
var AMERICAS = ['US','CA','MX','BR','AR','CL','CO','PE','VE','EC','BO','PY','UY','GY','SR','PA','CR','NI','HN','SV','GT','BZ','CU','JM','HT','DO','PR','TT','BB','BS','AG','DM','GD','KN','LC','VC','AW','CW','SX'];
var EMEA = ['GB','DE','FR','IT','ES','NL','BE','AT','CH','SE','NO','DK','FI','IE','PT','PL','CZ','RO','HU','GR','BG','HR','SK','SI','LT','LV','EE','LU','MT','CY','IL','AE','SA','QA','BH','KW','OM','JO','LB','IQ','IR','TR','EG','ZA','NG','KE','GH','TZ','ET','MA','TN','DZ','LY','SN','CI','CM','UG','AO','MZ','MG','RW','UA','RS','BA','ME','MK','AL','MD','GE','AM','AZ'];
var APAC = ['CN','JP','KR','IN','AU','NZ','SG','MY','TH','ID','PH','VN','TW','HK','MO','BD','PK','LK','NP','MM','KH','LA','BN','MN','FJ','PG','WS','TO','MV','AF','KZ','UZ','TM','KG','TJ'];
function getOrigin(cc) { if (AMERICAS.includes(cc)) return '0'; if (EMEA.includes(cc)) return '1'; if (APAC.includes(cc)) return '2'; return null; }
async function getKvs(key) { try { return await kvsHandle.get(key, { format: 'string' }); } catch(e) { return null; } }
async function handler(event) {
  var request = event.request;
  var cc = ((request.headers['x-viewer-country'] || {}).value || (request.headers['cloudfront-viewer-country'] || {}).value || '').toUpperCase();
  var originId = getOrigin(cc);

  // Check if preferred origin is enabled
  if (originId) {
    var enabled = await getKvs('origin_' + originId + '_enabled');
    if (enabled === 'false') { originId = null; }
  }

  // Fallback: find any healthy origin (priority: 0, 1, 2)
  if (!originId) {
    var candidates = ['0', '1', '2'];
    for (var idx = 0; idx < candidates.length; idx++) {
      var e = await getKvs('origin_' + candidates[idx] + '_enabled');
      if (e !== 'false') { originId = candidates[idx]; break; }
    }
  }

  // Last resort: use origin 0 even if marked unhealthy
  if (!originId) {
    originId = '0';
  }

  var domain = await getKvs('origin_' + originId + '_domain');
  if (domain) { cf.updateRequestOrigin({ domainName: domain, originId: 'origin-' + originId }); }
  request.headers['x-routed-origin'] = { value: originId };
  request.headers['x-routed-region'] = { value: originId };
  request.headers['x-viewer-country-resolved'] = { value: cc || 'UNKNOWN' };
  return request;
}
