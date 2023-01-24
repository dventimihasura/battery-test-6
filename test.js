import http from 'k6/http';
import { sleep } from 'k6';
export default function () {
    const headers = {'Content-Type': 'application/json'};
    const query = `query {test_${Math.floor(Math.random()*__ENV.N)+1} {id name}}`;
    // const query = `query {test_10 {id name}}`;
    const res = http.post('http://127.0.0.1:8080/v1/graphql', JSON.stringify({query: query}), {headers: headers});
}
