import http from 'k6/http';
import { sleep } from 'k6';
export default function () {
    const headers = {'Content-Type': 'application/json'};
    const query = `{"query":"query {test_${Math.floor(Math.random()*10)+1} {id name}}"}`
    const res = http.post('http://127.0.0.1:8081/v1/graphql', query, {headers: headers});
}
