import cf from 'cloudfront';

const kvsHandle = cf.kvs();

// Geo-to-origin mapping
// Americas (North + South America) → Origin 0
// EMEA (Europe, Middle East, Africa) → Origin 1
// APAC (Asia Pacific) → Origin 2

const AMERICAS = [
  'US','CA','MX','BR','AR','CL','CO','PE','VE','EC','BO','PY','UY','GY','SR',
  'PA','CR','NI','HN','SV','GT','BZ','CU','JM','HT','DO','PR','TT','BB','BS',
  'AG','DM','GD','KN','LC','VC','AW','CW','SX'
];

const EMEA = [
  'GB','DE','FR','IT','ES','NL','BE','AT','CH','SE','NO','DK','FI','IE','PT',
  'PL','CZ','RO','HU','GR','BG','HR','SK','SI','LT','LV','EE','LU','MT','CY',
  'IL','AE','SA','QA','BH','KW','OM','JO','LB','IQ','IR','TR','EG','ZA','NG',
  'KE','GH','TZ','ET','MA','TN','DZ','LY','SN','CI','CM','UG','AO','MZ','MG',
  'RW','UA','RS','BA','ME','MK','AL','MD','GE','AM','AZ'
];

const APAC = [
  'CN','JP','KR','IN','AU','NZ','SG','MY','TH','ID','PH','VN','TW','HK','MO',
  'BD','PK','LK','NP','MM','KH','LA','BN','MN','FJ','PG','WS','TO','MV','AF',
  'KZ','UZ','TM','KG','TJ'
];

function getRegionForCountry(countryCode) {
  if (AMERICAS.includes(countryCode)) return 'americas';
  if (EMEA.includes(countryCode)) return 'emea';
  if (APAC.includes(countryCode)) return 'apac';
  return null;
}

const REGION_TO_ORIGIN = {
  americas: '0',
  emea: '1',
  apac: '2'
};

async function getKvsValue(key) {
  try {
    return await kvsHandle.get(key, { format: 'string' });
  } catch (e) {
    return null;
  }
}

async function isOriginEnabled(originId) {
  const val = await getKvsValue(`origin_${originId}_enabled`);
  return val === 'true';
}

async function handler(event) {
  const request = event.request;
  
  // Get viewer country from CloudFront header
  const countryCode = (request.headers['x-viewer-country'] && 
                       request.headers['x-viewer-country'].value) || 
                      (request.headers['cloudfront-viewer-country'] &&
                       request.headers['cloudfront-viewer-country'].value) || '';

  const geoRegion = getRegionForCountry(countryCode.toUpperCase());
  let originId = geoRegion ? REGION_TO_ORIGIN[geoRegion] : null;
  let fallbackReason = null;

  // Check if the target origin is enabled
  if (originId) {
    const enabled = await isOriginEnabled(originId);
    if (!enabled) {
      fallbackReason = `origin_${originId}_maintenance`;
      originId = null; // fall to default
    }
  } else {
    fallbackReason = `unmapped_country_${countryCode || 'UNKNOWN'}`;
  }

  // Resolve domain
  let domain;
  if (originId) {
    domain = await getKvsValue(originId);
  }
  
  if (!domain) {
    // Fallback to default
    domain = await getKvsValue('__default__');
    if (fallbackReason) {
      // Log fallback to CloudWatch via console (CF Functions 2.0 supports console.log)
      console.log(JSON.stringify({
        event: 'geo_routing_fallback',
        reason: fallbackReason,
        country: countryCode,
        timestamp: new Date().toISOString()
      }));
    }
  }

  if (domain) {
    cf.updateRequestOrigin({ domainName: domain });
  }

  // Add routing metadata headers for the origin Lambda to echo back
  request.headers['x-routed-region'] = { value: geoRegion || 'default' };
  request.headers['x-routed-origin'] = { value: originId || 'default' };
  request.headers['x-viewer-country-resolved'] = { value: countryCode || 'UNKNOWN' };

  return request;
}
