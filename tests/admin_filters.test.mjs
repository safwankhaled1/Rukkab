import {test} from 'node:test';
import assert from 'node:assert/strict';
import {filterDemoRows,recordsCsv} from '../apps/admin/src/core/record_filters.ts';
test('CSV has real rows, Arabic BOM and neutralizes spreadsheet formulas',()=>{
 const csv=recordsCsv([{name:'  =HYPERLINK("fake")',value:'اسم عربي'},{name:'plain',value:'line\nnext'}],['name','value'],key=>key);
 assert.equal(csv.charCodeAt(0),0xfeff); assert.equal(csv.split('\r\n').length,3);
 assert.ok(csv.includes("'  =HYPERLINK")); assert.ok(csv.includes('اسم عربي')); assert.ok(csv.includes('""fake""'));
});
test('demo filters use Palestine civil dates, exact booleans, and numeric price ordering',()=>{
 const rows=[{id:'a',created_at:'2026-10-04T21:30:00Z',approved:false,total_price:30},{id:'b',created_at:'2026-10-04T20:30:00Z',approved:true,total_price:10},{id:'c',created_at:'2026-10-04T21:45:00Z',approved:false,total_price:5}];
 assert.deepEqual(filterDemoRows(rows,'',{from:'2026-10-05',to:'2026-10-05',approved:false},'price','bookings').map(row=>row.id),['c','a']);
 assert.equal(filterDemoRows(rows,'',{approved:true},'newest','vehicles').length,1);
});
