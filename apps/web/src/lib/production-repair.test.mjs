import test from 'node:test';
import assert from 'node:assert/strict';
import {safeUserMessage} from './user-message.ts';
import {androidAssociations,appleAssociations} from './mobile-associations.ts';
import {canUseManageTab} from './manage-access.ts';
test('safe bilingual errors never reveal diagnostics or private paths',()=>{
  for(const language of ['en','sw']) for(const message of ['permission denied for secret_table','SELECT * FROM payments',String.raw`C:\secret\key.json`]) {
    const output=safeUserMessage({message},language);assert.doesNotMatch(output,/secret_table|SELECT|key.json/);
  }
});
test('association documents require actual valid release identity',()=>{
  assert.deepEqual(androidAssociations({}),[]);assert.equal(appleAssociations({}),null);
  assert.throws(()=>androidAssociations({ANDROID_CUSTOMER_RELEASE_SHA256:'debug-placeholder'}));
  const fingerprint=Array(32).fill('AB').join(':');
  assert.equal(androidAssociations({ANDROID_CUSTOMER_RELEASE_SHA256:fingerprint})[0].target.package_name,'co.kodimali.customer_mobile');
  assert.throws(()=>appleAssociations({APPLE_TEAM_ID:'fake'}));
  assert.equal(appleAssociations({APPLE_TEAM_ID:'AB12345678'}).applinks.details[0].appIDs[0],'AB12345678.co.kodimali.customerMobile');
});
test('events navigation follows existing provider and coordinator permissions',()=>{
  assert.equal(canUseManageTab('agent',[],'events-provider'),true);
  assert.equal(canUseManageTab('admin',['events.manage'],'events-coordinator'),true);
  assert.equal(canUseManageTab('admin',['analytics.view'],'events-coordinator'),false);
  assert.equal(canUseManageTab('admin',['agents.manage','supervisor.scoped'],'events-coordinator'),false);
});
