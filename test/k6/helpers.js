import { check } from 'k6';
import http from "k6/http";

const USERPHONE = `917834811114`;
const PASSWORD = 'secret1234';
const BASE_URL = 'http://glific.test:4000';

export const post_gql = (query, access_token) => {
     let headers = {
         'Authorization': access_token,
         "Content-Type": "application/json"
     };

     let res = http.post(`${BASE_URL}/api`,
         JSON.stringify({query: query}), {headers: headers}
     );

     check(res, {
         'is status 200': (r) => r.status === 200,
     });

     // console.log(JSON.stringify(res.json('data')));
     if (res.status !== 200) {
         console.log(JSON.stringify(res.body));
     };

     return res.json('data');
};


export const  setup = () => {
    // register a new user and authenticate via a Bearer token.
    let loginRes = http.post(`${BASE_URL}/api/v1/session`, {
        "user[phone]": USERPHONE,
        "user[password]": PASSWORD
    });

    let access_token = loginRes.json('data').access_token;
    check(access_token, {
        'logged in successfully': () => access_token !== '',
    });

    return access_token;
}