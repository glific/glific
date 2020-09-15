import http from "k6/http";
import {check, group, sleep, fail} from 'k6';

// export let options = {
//     vus: 10,
//     duration: '1s',
// };

const USERPHONE = `917834811114`;
const PASSWORD = 'secret1234';
const BASE_URL = 'http://glific.test:4000';

export function setup() {
    // register a new user and authenticate via a Bearer token.
    let loginRes = http.post(`${BASE_URL}/api/v1/session`, {
        "user[phone]": USERPHONE,
        "user[password]": PASSWORD
    });

    let access_token = loginRes.json('data').access_token;
    check(access_token, { 'logged in successfully': () => access_token !== '', });

    return access_token;
}

function post_gql(query, access_token) {
    let headers = {
        'Authorization': access_token,
        "Content-Type": "application/json"
    };

    let res = http.post(`${BASE_URL}/api`,
                        JSON.stringify({ query: query }),
                        {headers: headers}
                       );

    check(res, {
        'is status 200': (r) => r.status === 200,
    });

    // console.log(JSON.stringify(res.json('data')));
    if (res.status !== 200) {
        console.log(JSON.stringify(res.body));
    };

    return res.json('data');
}

function tags_query() {
    return `
      query tags {
        tags {
          id
          label
        }
      }
    `;
}

function tags_create_query(label, shortcode) {
    let uniq = Math.random().toString(36).substr(2, 9)
    label = label + "_" + uniq
    shortcode += uniq

    return `
      mutation createTag {
        createTag(input: {label: "${label}", shortcode: "${shortcode}", language_id: 2}) {
          tag {
            id
            label
            language {
              id
              label
            }
          }
          errors {
            key
            message
          }
        }
      }
    `;
}

function tags_delete_query(id) {
    return `
      mutation deleteTag {
        deleteTag(id: ${id}) {
          tag {
            id
          }
          errors {
            key
            message
          }
        }
      }
    `;
}
export default function(access_token) {
    post_gql(tags_query(), access_token);
    sleep(1)
    let create_tag = post_gql(tags_create_query("new tag", "newtag"), access_token);
    sleep(1)
    post_gql(tags_delete_query(create_tag.createTag.tag.id), access_token)
    sleep(1)
}
