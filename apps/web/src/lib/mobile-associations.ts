type AssociationEnvironment = Record<string, string | undefined>;
export function androidAssociations(env: AssociationEnvironment) {
  const entries = [
    ["co.kodimali.customer_mobile", env.ANDROID_CUSTOMER_RELEASE_SHA256],
    ["co.kodimali.manage_mobile", env.ANDROID_MANAGE_RELEASE_SHA256],
  ].flatMap(([packageName, raw]) => {
    const fingerprints=(raw ?? "").split(",").map(value=>value.trim()).filter(Boolean);
    if (!fingerprints.length) return [];
    if (!fingerprints.every(value=>/^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$/.test(value))) throw new Error("Invalid release certificate fingerprint");
    return [{relation:["delegate_permission/common.handle_all_urls"],target:{namespace:"android_app",package_name:packageName,sha256_cert_fingerprints:fingerprints}}];
  });
  return entries;
}
export function appleAssociations(env: AssociationEnvironment) {
  const team=env.APPLE_TEAM_ID;
  if (!team) return null;
  if (!/^[A-Z0-9]{10}$/.test(team)) throw new Error("Invalid Apple team identifier");
  return {applinks:{details:[{appIDs:[`${team}.co.kodimali.customerMobile`],components:[{"/":"/listing/*"},{"/":"/account/request/*"},{"/":"/account"}]}]}};
}
