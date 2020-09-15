import { sleep} from 'k6';
import {
  post_gql,
  setup as setup_helper
} from './helpers.js';

// export let options = {
//     vus: 10,
//     duration: '1s',
// };

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

export const setup = () => setup_helper()

export default function(access_token) {
    post_gql(tags_query(), access_token);
    sleep(1)
    let create_tag = post_gql(tags_create_query("new tag", "newtag"), access_token);
    sleep(1)
    post_gql(tags_delete_query(create_tag.createTag.tag.id), access_token)
    sleep(1)
}