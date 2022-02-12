defmodule Glific.Clients.NayiDisha.Data do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  @parent_hsm_uuid_advise_eng "2f9c4fb1-2bcb-4f8d-b9a0-80e366e1e43d"
  @parent_hsm_uuid_advise_hn "1ae7a7b2-a89d-409b-b5c4-750ee232c98c"
  @parent_hsm_uuid_poster_eng "f9c9facc-4f78-4351-807c-193f491471e3"
  @parent_hsm_uuid_poster_hn "b57e52fc-380a-4fb1-9d20-ccf16c5384af"

  @hsm %{
    1 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Covid 19 cases are still on the rise. Therefore, we request you to continue taking preventive measures at all times. In this question series Neuro-Developmental Pediatrician Dr. Ajay Sharma talks about some common concerns about Covid-19 and and vaccinations to manage the illness in children who need special care. Dr.Ajay Sharma is a consultant Neurodevelopmental Paediatrician and the ex-Clinical Director at Evelina London, Guy’s and St Thomas’ Hospital, UK. Click on this link to listen to the question series👉 https://nayi-disha.org/article/covid-19-care-illness-and-its-vaccine-special-children-english/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "कोविड -19 के मामले बढ़ रहे हैं और हम आप सभी से अनुरोध करते हैं कि कोविड से बचने की सावधानियों का पालन करते रहें ।इस प्रश्न श्रृंखला में न्यूरो-डेवलपमेंटल पीडियाट्रिशियन, डॉ. अजय शर्मा कोविड -19 के बारे में कुछ सामान्य चिंताओं, बीमारी के प्रबंधन के लिए टीकाकरण के बारे में बात करते हैं, ख़ास तौर से उन बच्चों में जिन्हें विशेष देखभाल की आवश्यकता होती है। डॉ. अजय शर्मा एवेलीना हॉस्पिटल, इंग्लैंड के न्यूरो-डेवलपमेंटल पेडिअट्रिशन (परामर्शदाता) और सत. थॉमस हॉस्पिटल, इंग्लैंड के पूर्व क्लीनिकल डायरेक्टर है। प्रश्न श्रृंखला को सुनने के लिए यह लिंक दबाएं 👉 https://nayi-disha.org/hi/article/covid-19-care-illness-and-its-vaccine-special-children-english/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Covid 19 cases are still on the rise. Therefore, we request you to continue taking preventive measures at all times. In this question series Neuro-Developmental Pediatrician Dr. Ajay Sharma talks about some common concerns about Covid-19 and and vaccinations to manage the illness in children who need special care. Dr.Ajay Sharma is a consultant Neurodevelopmental Paediatrician and the ex-Clinical Director at Evelina London, Guy’s and St Thomas’ Hospital, UK. Click on this link to listen to the question series👉 https://nayi-disha.org/article/covid-19-care-illness-and-its-vaccine-special-children-english/"
          ]
        }
      }
    },
    2 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "As the world continues to battle with Covid 19, we request you to continue taking preventive measures at all times. In this question series Neuro-Developmental Pediatrician Dr. Ajay Sharma talks about some common concerns coping with the needs of special children at home during the Covid-19 pandemic. Click on this link to listen to the question series👉  https://nayi-disha.org/article/covid-19-care-coping-needs-special-children-home-english/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "आज पूरी दुनिया कोविड 19 से जूझ रही है, हम आपसे हर समय निवारक उपाय जारी रखने का अनुरोध करते हैं। इस प्रश्न श्रृंखला में न्यूरो-डेवलपमेंटल पीडिएट्रिशन डॉ. अजय शर्मा  कोविद -19 महामारी के दौरान विशेष आवश्यकताओं से प्रभावित बच्चों की देखभाल के बारे में बच्चों की घर पर मदद करने के तरीके समझाते हैं। प्रश्न श्रृंखला को सुनने के लिए यह लिंक दबाएं 👉  https://nayi-disha.org/hi/article/covid-19-care-coping-needs-special-children-home-english/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "As the world continues to battle with Covid 19, we request you to continue taking preventive measures at all times. In this question series Neuro-Developmental Pediatrician Dr. Ajay Sharma talks about some common concerns coping with the needs of special children at home during the Covid-19 pandemic. Click on this link to listen to the question series👉  https://nayi-disha.org/article/covid-19-care-coping-needs-special-children-home-english/"
          ]
        }
      }
    },
    3 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "The battle with Covid 19 is still on. Therefore, we urge you to continue taking preventive measures at all times. In case the primary caregiver has to be quarantined due to Covid-19, create a list of things that will come in handy for the next person in line of caregiving to ensure the individual being cared for feels safe and will continue to be in good hands at all times. List can include the following details:- *1)* Medication regularly used by the individual with IDD with doctor's prescription💊📝 *2)* Names and numbers of therapy centers, doctors or counselor🩺☎️ *3)* Legal documents such as the Disability certificate, Guardianship form, Identity card 📄📃 *4)* List out a set of toys, tools or activities that entertain or help calm the individual 🧸🏎️ *5)* Specific food preferences, allergies or intolerances, if any.🥕🥗 *6)* Please find the Caregiver's Emergency Chart chart here 👉  https://nayi-disha.org/article/caregivers-guidance-chart/?lang=English"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "माता-पिता एवं केयरगिवर के लिए आज का संदेश 👉 कोविड-19 से जंग अभी जारी है। इसलिए, हम आपसे हर समय निवारक उपाय जारी रखने का आग्रह करते हैंl ऐसे समय में इस बीमारी से सम्बंधित संभव कठिनाइयों के लिए तैयार रहना उचित रहेगा। यदि भविष्य में मुख्य देखभाल कर्ता कोविड-19 से संक्रमित होता है, तो वह अगले देखभाल कर्ता के सहायता लिए निम्नलिखित जानकारी प्रदान कर सकता है| *1)* विकलांग व्यक्ति की रोज़मर्रा की दवाईयां (डॉक्टर प्रिस्क्रिप्शन समेत)💊📝 *2)* काउंसलर, डॉक्टर एवं थेरेपी केंद्रों के नाम तथा टेलीफोन नंबर 🩺☎️ *3)* कानूनी दस्तावेज़- जैसे विकलांगता प्रमाण पत्र, गार्डियन शिप फॉर्म, पहचान पत्र 📄📃 *4)* विशिष्ट उपकरण/ खिलौने जो विकलांग व्यक्ति को दुखी या उदास से सामान्य स्तिथि में लाने में मदद करे 🧸🏎️ *5)* विशिष्ट खाद्य प्राथमिकताएं (एलर्जी या असहिष्णुता) 🥕🥗 *6)* कृपया देखभाल करने वाले के लिए आपातकालीन गाइड को यहां देखें 👉 https://nayi-disha.org/hi/article/caregivers-guidance-chart/?lang=English"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "The battle with Covid 19 is still on. Therefore, we urge you to continue taking preventive measures at all times. In case the primary caregiver has to be quarantined due to Covid-19, create a list of things that will come in handy for the next person in line of caregiving to ensure the individual being cared for feels safe and will continue to be in good hands at all times. List can include the following details:- *1)* Medication regularly used by the individual with IDD with doctor's prescription💊📝 *2)* Names and numbers of therapy centers, doctors or counselor🩺☎️ *3)* Legal documents such as the Disability certificate, Guardianship form, Identity card 📄📃 *4)* List out a set of toys, tools or activities that entertain or help calm the individual 🧸🏎️ *5)* Specific food preferences, allergies or intolerances, if any.🥕🥗 *6)* Please find the Caregiver's Emergency Chart chart here 👉  https://nayi-disha.org/article/caregivers-guidance-chart/?lang=English"
          ]
        }
      }
    },
    4 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Enlisted below are things to be kept in mind if a member of the family is Covid-19 positive *1)* Identify two or more caregivers in the event that the immediate caregiver falls ill/infected *2)* Have a plan in place to self-quarantine as a care-giver away from the person with IDD *3)* Ensure there are a couple of people at home who interact with the person with IDD on a regular basis.If this is not possible, keep in touch with the school teachers/therapists who know the child well *4)* Please fill all details in the “Caregivers Emergency Guide” provided. Walk the caregiver through all sections of the chart while handing it over to her/him *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "माता-पिता एवं केयरगिवर के लिए आज का संदेश 👉 अगर आप या परिवार का कोई सदस्य कोविद-१९ से संक्रमित होता है तो इन चीजों को ध्यान में रखें :- *~* ऐसे आपात परिस्थितियों के लिए २ या अधिक व्यक्तियों को विकलांग व्यक्ति की देखभाल के लिए पहले से नियुक्त करके रखे । *~* यदि आपको देखभाल कर्ता के तौर पर अकेले (सेल्फ क्वॉरेंटाइन) रहने की आवश्यकता हो तो उसकी योजना भी पहले से ही बना ले। *~* यह सुनिश्चित करें कि घर में एक या दो व्यक्तियों का विकलांग व्यक्ति के साथ मेलजोल बना रहे।यदि यह संभव नहीं है तो बच्चे को अच्छी तरह से जानने वाले उसके टीचर या थेरेपिस्ट से संपर्क बनाए रखें। *~* आपको भेजे गए 'देखभाल करने वाले मार्गदर्शन
            जांच सूची' में अपने बच्चे से सम्बंधित जानकारी भरे और याद से नियुक्त देखभाल कर्ता को सौपें। विस्तृत निर्देश देने के लिए उनको 'चार्ट' के हर पहलू समझाएं । *~* हमारे सभी संसाधन उपयोग करने के लिए फ्री हैं। साइन-इन करें ताकि हम आपको बेहतर सेवा देने के लिए संसाधन उपयोग को ट्रैक कर सकें!"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Enlisted below are things to be kept in mind if a member of the family is Covid-19 positive *1)* Identify two or more caregivers in the event that the immediate caregiver falls ill/infected *2)* Have a plan in place to self-quarantine as a care-giver away from the person with IDD *3)* Ensure there are a couple of people at home who interact with the person with IDD on a regular basis.If this is not possible, keep in touch with the school teachers/therapists who know the child well *4)* Please fill all details in the “Caregivers Emergency Guide” provided. Walk the caregiver through all sections of the chart while handing it over to her/him *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
          ]
        }
      }
    },
    5 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Today's message for parents and caregivers👉 Remember the lessons this pandemic taught us and plan your child's future accordingly. The 6 documents/processes mentioned below are vital for your child's secure future. ⚪ Disability Certificate 🟠 UDID 🔵 Legal Guardianship Certificate 🔴 Letter of Intent 🟡  Will 🟢 Financial Planning *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "माता-पिता एवं केयरगिवर के लिए आज का संदेश 👉 कोरोना महामारी को न भूले और उसके परिणाम से सीखे। अपने बच्चे के भविष्य की योजनाओं में निवेश करे ताकि कल के आपात स्तिथि में आप तैयार हो। अपने बच्चे के कानूनी और वित्तीय भविष्य को सुरक्षित रखने के लिए इन ६ दस्तावेज़ो का प्रबन्द ज़रूर करे। ⚪ डिसेबिलिटी सर्टिफिकेट (विकलांगता प्रमाण पत्र) 🟠 यू.डी.आई.डी 🔵 लीगल गार्डियनशिप सर्टिफिकेट (विधिक संरक्षकता प्रमाण पत्र)🔴 लेटर ऑफ़ इंटेंट (विशिष्ट उद्देश्य पत्र)🟡 वसीयत 🟢 वित्तीय योजना *हमारे सभी संसाधन उपयोग करने के लिए फ्री हैं। साइन-इन करें ताकि हम आपको बेहतर सेवा देने के लिए संसाधन उपयोग को ट्रैक कर सकें!*"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Today's message for parents and caregivers👉 Remember the lessons this pandemic taught us and plan your child's future accordingly. The 6 documents/processes mentioned below are vital for your child's secure future. ⚪ Disability Certificate 🟠 UDID 🔵 Legal Guardianship Certificate 🔴 Letter of Intent 🟡  Will 🟢 Financial Planning *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
          ]
        }
      }
    },
    6 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Disability Certificate* *1)* Disability certificate is issued to all individuals with disabilities that are recognized under the Persons with Disabilities Act, 2016. The minimum degree of disability for each category of disability must be met *2)* The individual applying for the certificate must be an Indian Citizen. *3)* The certificate is given for 3 years only for PwD below 18 years of age. The certificate is valid for life for PwD who are above 18 years of age. Click on this link for more information 👉 https://www.nayi-disha.org/article/how-apply-disability-certificate-india *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*विक्लांग्ता प्रमाण पत्र (डिसेबिलिटी सर्टिफिकेट)* *१)* यदि आपको/आपके परिजन को इन कार्यों (चलना, सुनना, देखना, बोलना, समझना, समिल्लित करना) में से किसी एक या अधिक को दर्शाने में असमर्थ होते हैं, तो आप विकलांगता प्रमाणपत्र के लिए आवेदन कर सकते है। *२)* विकलांगता प्रमाणपत्र के लिए व्यक्ति का भारतीय मूल का नागरिक होना अनिवार्य है। प्रत्येक व्यक्ति अधिनियम में निर्देशित विकलांगता की न्यूनतम सीमा से प्रभावित होगा। *३)* वैधता- 18 वर्ष से कम के व्यक्ति के लिए विक्लांग्ता प्रमाणपत्र 3 वर्ष की अवधि के लिए बनाया जाता है। 18 वर्ष से अधिक की आयु होने पर विकलांग व्यक्ति का प्रमाणपत्र आजीवन वैध रहता है। अधिक जानकारी के लिए यह लिंक दबाए 👉 https://nayi-disha.org/hi/article/how-apply-disability-certificate-india/ *हमारे सभी संसाधन उपयोग करने के लिए फ्री हैं। साइन-इन करें ताकि हम आपको बेहतर सेवा देने के लिए संसाधन उपयोग को ट्रैक कर सकें!*"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Disability Certificate* *1)* Disability certificate is issued to all individuals with disabilities that are recognized under the Persons with Disabilities Act, 2016. The minimum degree of disability for each category of disability must be met *2)* The individual applying for the certificate must be an Indian Citizen. *3)* The certificate is given for 3 years only for PwD below 18 years of age. The certificate is valid for life for PwD who are above 18 years of age. Click on this link for more information 👉 https://www.nayi-disha.org/article/how-apply-disability-certificate-india *All our resources are free to use. Sign-in so we can track resource usage to serve you better!*"
          ]
        }
      }
    },
    7 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Disability Certificate*-Important documents for the application process. *1* 2 passport size photographs *2* Copy of Government I.D. like Aadhar card of the PwD *3* Copy of Government I.D. like Aadhar of parents *4* Copy of all medical and psychological reports of the individual"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "विक्लांग्ता प्रमाण पत्र (डिसेबिलिटी सर्टिफिकेट)- ज़रूरी दस्तावेज़ *~* 2 पासपोर्ट आकार की फोटो *~* सरकारी पहचान पत्र की प्रति (आवेदन करने वाले व्यक्ति का आधार कार्ड/पासपोर्ट/ड्राइविंग लाइसेंस) *~* आवेदन करने वाले व्यक्ति के अभिभावकों के सरकारी पहचान पत्र प्रति *~* आवेदक की सभी प्रकार की चिकित्सकीय व मानसिक रिपोर्ट की प्रतियाँ"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Disability Certificate*-Important documents for the application process. *1* 2 passport size photographs *2* Copy of Government I.D. like Aadhar card of the PwD *3* Copy of Government I.D. like Aadhar of parents *4* Copy of all medical and psychological reports of the individual"
          ]
        }
      }
    },
    8 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Disability Certificate*- Evaluation Every individual with a disability will be evaluated in three areas – *1)* Clinical- General analysis by a medical doctor and/or physiotherapist/OT *2)* Behavioral- Psychological evaluation by psychologist *3)* Intellectual Functioning- Learning & communication abilities are assessed by a special educator & speech language pathologist"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "विकलांगता प्रमाण पत्र (डिसेबिलिटी सर्टिफिकेट)- मूल्यांकन विकलांगता से प्रभावित व्यक्ति को तीन प्रकार की जांच से गुजरना होता है – *१)* चिकित्सकीय मूल्यांकन -चिकित्सक और/अथवा फिजियोथेरेपिस्ट/ओटी और/अथवा दृष्टि विशेषज्ञ और/अथवा श्रवण विशेषज्ञ के द्वारा *२)* व्यावहारिक मूल्यांकन- उसी स्थान से मनोवैज्ञानिक द्वारा होता है जहां से प्रमाणपत्र जारी किया जाता है *३)* बौद्धिक कार्यक्षमता- चिकित्सक के द्वारा सभी मूल्यांकन सम्पूर्ण होने के बाद प्रत्येक व्यक्ति की परीक्षण रिपोर्ट तैयार की जाती है।विकलांगता प्रमाणपत्र प्राप्त करने के लिए यह एक महत्वपूर्ण दस्तावेज़ माना जाता है।"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Disability Certificate*- Evaluation Every individual with a disability will be evaluated in three areas – *1)* Clinical- General analysis by a medical doctor and/or physiotherapist/OT *2)* Behavioral- Psychological evaluation by psychologist *3)* Intellectual Functioning- Learning & communication abilities are assessed by a special educator & speech language pathologist"
          ]
        }
      }
    },
    9 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Disability Certificate* In India, this certificate is usually issued by authorized medical authorities (or a board). The PwD and their parents must apply for the disability certificate from specific authorized Medical centers/hospitals. The certificate is processed by the Government. Use the certificate to avail government benefits."
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "विकलांगता प्रमाण पत्र (डिसेबिलिटी सर्टिफिकेट)- भारत में, सामान्य रूप से यह प्रमाणपत्र चिकित्सा कार्यालयों (अथवा बोर्ड) के द्वारा जारी किया जाता है।दिव्याङ्ग जन और उनके माता-पिता को विकलांगता प्रमाणपत्र प्राप्त करने के लिए विशिष्ट अस्पताल और अधिकृत चिकित्सा केंद्र/अस्पताल में आवेदन करना चाहिए। जांच रिपोर्ट को विकलांग व्यक्ति को सौंप दी जाती है। इस प्रमाणपत्र का निर्माण सरकार के द्वारा किया जाता है। सरकारी सुविधाओं का उपयोग करने के लिए विकलांगता प्रमाणपत्र का प्रयोग करें |"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Disability Certificate* In India, this certificate is usually issued by authorized medical authorities (or a board). The PwD and their parents must apply for the disability certificate from specific authorized Medical centers/hospitals. The certificate is processed by the Government. Use the certificate to avail government benefits."
          ]
        }
      }
    },
    10 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*UDID* *1)* UDID for people with disabilities is an identification card for a person with a disability (PwD) *2)* It aims at building an integrated system for the issuance of UDID and Disability Certificate. *3)* The card includes the demographic details and disability-related information of PWD across the country. A person having a disability that is under RPWD Act 2016 is eligible for the UDID. Click on this link for more information 👉 https://nayi-disha.org/article/how-to-apply-for-udid/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*UDID* *1)* विकलांग लोगों के लिए यूडीआईडी ​​​​विकलांग व्यक्ति (पीडब्ल्यूडी) के लिए एक पहचान पत्र है। *2)* इसका उद्देश्य यूडीआईडी ​​और विकलांगता प्रमाण पत्र जारी करने के लिए एक एकीकृत प्रणाली का निर्माण करना है। *3)* कार्ड में देश भर के पीडब्ल्यूडी के जनसांख्यिकीय विवरण और विकलांगता संबंधी जानकारी शामिल है। आरपीडब्ल्यूडी अधिनियम 2016 के तहत विकलांग व्यक्ति यूडीआईडी ​​के लिए पात्र है। अधिक जानकारी के लिए इस लिंक पर क्लिक करें 👉 https://nayi-disha.org/hi/article/udid-for-people-with-disabilities/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*UDID* *1)* UDID for people with disabilities is an identification card for a person with a disability (PwD) *2)* It aims at building an integrated system for the issuance of UDID and Disability Certificate. *3)* The card includes the demographic details and disability-related information of PWD across the country. A person having a disability that is under RPWD Act 2016 is eligible for the UDID. Click on this link for more information 👉 https://nayi-disha.org/article/how-to-apply-for-udid/"
          ]
        }
      }
    },
    11 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about UUID"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["यूयूआईडी के बारे में "],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about UUID"],
        }
      }
    },
    12 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about more information related to UUID"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["यूआईडी से संबंधित अधिक जानकारी के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about more information related to UUID"],
        }
      }
    },
    13 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about self-care"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["खुद की देखभाल के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about self-care"],
        }
      }
    },
    14 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Legal Guardianship* - The Guardian needs to be a blood relative. Discuss and seek written consent from your candidates for the Guardianship📝 . It is better to keep the Guardian and Trustee separate as the Guardian also manages the personal affairs👩‍👧, whereas a Trustee will handle proceedings of the Trust deed i.e. the financial affairs of the child. A Guardian has NO say over what you have specified in the Will for your child📜. If the guardian is not taking good care of the child, the court may overturn the parent appointed legal guardian. For more information, please click on this link- https://www.nayi-👉 disha.org/article/choosing-guardian-my-child-financial-planning-my-special-child"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "लीगल गार्डियन या वैध/कानूनी पालक माता पिता के अनुपस्थिति में, एक रक्त सम्बन्धी ही बच्चे का कानूनी पालक हो सकता है।आमतौर पर, निश्चित उम्मीदवार से लिखित सहमति लेना उचित रहता है📝 । अगर बच्चे का कोई भी रक्त सम्बन्धी जीवित नहीं है, आपके परिवार के दूसरे सदस्य (जैसे भाभी, चाची, मामी), बच्चे के वैध पालक बन सकते है 👩‍👧। बेहतर है की ट्रस्टी और पालक अलग अलग व्यक्ति ही हो क्योकि पालक व्यक्तिगत मामले ही संभालता है। वसीयत में पालक का कोई हस्तक्षेप नहीं होता 📜। अगर पालक बच्चे का उचित ख्याल नहीं रखता, न्यायालय माता पिता का निर्णय उलट सकता है 👨‍⚖️ । अधिक् जानकारी के लिए यह लिंक दबाएं 👉 https://nayi-disha.org/hi/article/choosing-guardian-my-child-financial-planning-my-special-child/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Legal Guardianship* - The Guardian needs to be a blood relative. Discuss and seek written consent from your candidates for the Guardianship📝 . It is better to keep the Guardian and Trustee separate as the Guardian also manages the personal affairs👩‍👧, whereas a Trustee will handle proceedings of the Trust deed i.e. the financial affairs of the child. A Guardian has NO say over what you have specified in the Will for your child📜. If the guardian is not taking good care of the child, the court may overturn the parent appointed legal guardian. For more information, please click on this link- https://www.nayi-👉 disha.org/article/choosing-guardian-my-child-financial-planning-my-special-child"
          ]
        }
      }
    },
    15 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Legal Guardianship- Application Process* - There are two processes – National Trust recognizes four levels of disabilities. Check if your child qualifies to come under these four sections. If yes, then you can apply it through their LLC (Local level committee) process in your State. If the child doesn’t fall under the four specified categories, or if LLC isn’t available in your resident city then you have to apply for guardianship at the sub-divisional magistrate office in your State. It may take 3-4months to get the guardian certificate. Please click on this link to find more resources on Financial Advisors👉  https://nayi-disha.org/directory-search-results/?ucategory=financial-and-legal-services&ulocation=All%20Cities&homeconsult=undefined&videoconsult=undefined&distance=undefined&rating=undefined&age_group=undefined&condition=undefined"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*लीगल गार्डियन* अगर आपका बच्चा राष्ट्र न्यास द्वारा कथित किसी भी विकलांग श्रेणी में आता है, तो आप स्थानीय स्तर की समिति (लोकल लेवल कमिटी) से पालक का आवेदन कर सकते है। स्थानीय स्तर की समिति के अनुपस्थिति में आप सब-डिविशनल मजिस्ट्रेट ऑफिस से पालक का आवेदन कर सकते है।राष्ट्रीय न्यास द्वारा नियुक्त पालक की उपस्थिति में, आपको कोर्ट द्वारा नियुक्त पालक की आवश्यकता नहीं है। वित्तीय सलाहकारों (फाइनेंसियल एडवाइजर) पर अधिक संसाधन खोजने के लिए कृपया इस लिंक पर क्लिक करें 👉https://nayi-disha.org/directory-search-results/?ucategory=financial-and-legal-services&ulocation=All%20Cities&homeconsult=undefined&videoconsult=undefined&distance=undefined&rating=undefined&age_group=undefined&condition=undefined "
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Legal Guardianship- Application Process* - There are two processes – National Trust recognizes four levels of disabilities. Check if your child qualifies to come under these four sections. If yes, then you can apply it through their LLC (Local level committee) process in your State. If the child doesn’t fall under the four specified categories, or if LLC isn’t available in your resident city then you have to apply for guardianship at the sub-divisional magistrate office in your State. It may take 3-4months to get the guardian certificate. Please click on this link to find more resources on Financial Advisors👉  https://nayi-disha.org/directory-search-results/?ucategory=financial-and-legal-services&ulocation=All%20Cities&homeconsult=undefined&videoconsult=undefined&distance=undefined&rating=undefined&age_group=undefined&condition=undefined"
          ]
        }
      }
    },
    16 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Legal Guardianship* Who is a Legal Guardian? Legal Guardianship is the legal process of appointing a legal guardian to the PwD, who has the authority to make decisions on all personal matters (in some cases financial too) on behalf of the PwD, to suit his/her best interests. Who are the key players in a legal guardianship process? *~* 👨‍👩‍👧 Biological Parents of the PwD *~* 👱👶Person with Disability (PwD) *~* 👨‍👩‍👧‍👦Family Members- Blood-related family members may be designated guardians in lieu of the inability or absence of biological parents to become Guardians themselves. *~* Registered Organisation-In absence of relatives, LLC may direct a Registered Organization(RO) to become the guardian instead. *~* Local Level Committee (LLC)-A district level committee who approves, appoints and monitors the legal guardian of a PwD. The committee must have an officer of the rank of District Magistrate or Deputy Commissioner of the district For more information please click on this link 👉  https://nayi-disha.org/article/how-do-you-apply-legal-guardianship-special-child/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*१)* लीगल गार्डियन कौन होता है? *१)* गार्डियनशिप एक कानूनी प्रक्रिया होती है जिससे आप अपने बच्चे के देख रेख के लिए एक व्यक्ति (लीगल गार्डियन) को नियुक्त कर सकते है। बच्चे के व्यक्तिगत मामलो के साथ साथ गार्डियन को बच्चे के हित के लिए उनके तरफ से कानूनी कर्त्तव्य भी निभाने पढ़ते है। *२)* लीगल गार्डियनशिप की प्रक्रिया में कौन कौन शामिल होता है? *२)* *~* 👨‍👩‍👧 बच्चे के जैविक माता पिता *~* 👱👶विकलांग बच्चा *~* 👨‍👩‍👧‍👦परिवार जन- रक्त सम्बन्धी परिवार जन जो जैविक माता पिता के अनुपस्थिति में नामित गार्डियन बन सके *~* पंजीकृत संगठन- रक्त सम्बन्धियों के अनुपस्थिति में एल.एल.सी एक पंजीकृत संगठन को गार्डियन की भूमिका निभाने को कह सकता है। *~* लोकल लेवल कमीटी (एल.एल.सी)- यह जिला के स्तर की समिति होती है जो लीगल गार्डियन को मंज़ूरी, नियुक्ति और निगरानी रखती है। समिति में एक डिस्ट्रिक्ट मजिस्ट्रेट (डी.एम्.), डिप्टी कमिश्नर या उस पद का कोई और अधिकारी ज़रूर होना चाहिए। अधिक् जानकारी के लिए यह लिंक दबाएं - https://nayi-disha.org/hi/article/how-do-you-apply-legal-guardianship-special-child/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Legal Guardianship* Who is a Legal Guardian? Legal Guardianship is the legal process of appointing a legal guardian to the PwD, who has the authority to make decisions on all personal matters (in some cases financial too) on behalf of the PwD, to suit his/her best interests. Who are the key players in a legal guardianship process? *~* 👨‍👩‍👧 Biological Parents of the PwD *~* 👱👶Person with Disability (PwD) *~* 👨‍👩‍👧‍👦Family Members- Blood-related family members may be designated guardians in lieu of the inability or absence of biological parents to become Guardians themselves. *~* Registered Organisation-In absence of relatives, LLC may direct a Registered Organization(RO) to become the guardian instead. *~* Local Level Committee (LLC)-A district level committee who approves, appoints and monitors the legal guardian of a PwD. The committee must have an officer of the rank of District Magistrate or Deputy Commissioner of the district For more information please click on this link 👉  https://nayi-disha.org/article/how-do-you-apply-legal-guardianship-special-child/"
          ]
        }
      }
    },
    17 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Legal Guardianship* Who can be the legal guardian of your child? *1)* Biological Parents *2)* Siblings *3)* Blood-Related Family Members *4)* Registered Organisation Parents are considered the legal guardians of their ward until the ward is 18years of age. Once the child turns into an adult (>18years of age) the parents need to apply for Guardianship under the norms laid out by National Trust. A potential Legal guardian must have the following qualities:- *1)* Individual must be a citizen of India *2)* Individual is of sound mind *3)* Individual must have no prior or current criminal record and/or pending court cases *4)* Individual must be financially independent *5)* In case of an RO, the organization should be registered with the state social welfare department"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "विकलांग व्यक्ति का लीगल गार्डियन कौन बन सकता है?*१)* जैविक माता मिटा 👨‍👩‍👧 *२)* भाई बहन 👫 *३)* रक्त समबंधी परिवार जन 👨‍👩‍👧‍👦 *४)* पंजीकृत संस्थान (रजिस्टर्ड आर्गेनाईजेशन- आर.ओ.) माता पिता अपने बच्चे के लीगल गार्डियन उसके १८ वर्ष होने तक ही रह सकते है। राष्ट्रीय न्यास (नेशनल ट्रस्ट) के नियमों के अनुसार, विक्लांग बच्चे के १८ वर्ष होने के बाद, माता पिता को उसका लीगल गार्डियन बनने के लिए आवेदन करना पढ़ता है। एक लीगल गार्डियन में यह विशिष्टताऐं होना ज़रूरी है👇 ॰भारतीय नागरिक 🇮🇳 ॰जिसका कोई आपराधिक रिकॉर्ड या लंबित कोर्ट केस न हो ⚖ ॰ जो आर्थिक रूप से आत्मनिर्भर हो 💵 ॰अगर एक आर.ओ. को गार्डियन की भूमिका निभानी पढ़े तो उसको राज्य के सामाजिक कल्याण विभाग (सोशल वेलफेयर डिपार्टमेंट) के साथ पंजीकृत होना चाहिए| "
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Legal Guardianship* Who can be the legal guardian of your child? *1)* Biological Parents *2)* Siblings *3)* Blood-Related Family Members *4)* Registered Organisation Parents are considered the legal guardians of their ward until the ward is 18years of age. Once the child turns into an adult (>18years of age) the parents need to apply for Guardianship under the norms laid out by National Trust. A potential Legal guardian must have the following qualities:- *1)* Individual must be a citizen of India *2)* Individual is of sound mind *3)* Individual must have no prior or current criminal record and/or pending court cases *4)* Individual must be financially independent *5)* In case of an RO, the organization should be registered with the state social welfare department"
          ]
        }
      }
    },
    18 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about legal guardianship"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["कानूनी संरक्षकता के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about legal guardianship"],
        }
      }
    },
    19 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Caregiver Stress Management* - It is important to take care of yourself in this stressful time. For more information please click on this link 👉  https://nayi-disha.org/article/caregiver-stress-management-taking-care-yourself/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*देखभालकर्ता तनाव प्रबंधन* - इस तनावपूर्ण समय में अपना ख्याल रखना जरूरी है। अधिक जानकारी के लिए कृपया इस लिंक पर क्लिक करें 👉 https://nayi-disha.org/hi/article/caregiver-stress-management-taking-care-yourself/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Caregiver Stress Management* - It is important to take care of yourself in this stressful time. For more information please click on this link 👉  https://nayi-disha.org/article/caregiver-stress-management-taking-care-yourself/"
          ]
        }
      }
    },
    20 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Letter of Intent* A LOI as it is known is not a legal document but a description about your child’s life and vision. This one document passes on vital information about your child to the future caretaker(s). You can include the following sections to your letter of intent:- *1)* Family History- Details about child’s birth, place of residence, school, relatives and parents’ vision for the child *2)* Living- Overview about your child’s living, daily routine, affairs, habits, likes and dislikes *3)* Education and employment- Details about current education of the child, special classes, special schools, recreational/extracurricular activities, vocational trainings. *4)* Health Care- Details about current health condition of the child, with detailed history of the child’s healthcare since birth. Specific names of doctors, therapists, clinics, hospitals etc. may be included in this section for future reference. For more information on sections of letter of intent, click on this link 👉 https://www.nayi-disha.org/article/letter-intent-your-child-special-needs"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*विशिष्ट उद्देश्य पत्र (लेटर ऑफ़ इंटेंट)* विशिष्ट उद्देश्य पत्र (लेटर ऑफ़ इंटेंट), हालांकि कोई कानूनी दस्तावेज़ नहीं होता है, लेकिन इसमें आपके बच्चे की जिंदगी और उससे जुड़े विभिन्न पहलुओं के बारे में स्पष्ट लिखा जाता है। इस एक दस्तावेज़ के माध्यम से बच्चे के भावी संरक्षक/संरक्षकों को उससे जुड़ी हर प्रकार की महत्वपूर्ण जानकारी सरलता से प्राप्त हो जाती है। एक सामान्य विशिष्ट उद्देश्य पत्र को निम्न अनुभागों में बांटते हुए तैयार किया जा सकता है:- *१)* पारिवारिक इतिहास- जन्म स्थान, स्कूल, निवास स्थान, परिवार सदस्य का विस्तार से वर्णन करे *२)* जीवनयापन-प्रतिदिन किए जाने वाले काम जैसे उसके उठने का समय, वह क्या करता/करती है और उसका रोज़ का क्या दिनचर्या है आदि महत्वपूर्ण जानकारी देनी चाहिए *३)* शिक्षा और रोजगार- बच्चे की वर्तमान शिक्षा, विशेष कक्षाओं, विशेष विद्यालयों, मनोरंजक/पाठ्येतर गतिविधियों, व्यावसायिक प्रशिक्षणों के बारे में विवरण। *४)* स्वास्थ्य सुरक्षा- बच्चे के विशिष्ट चिकित्सकों के नाम, दवाइयां, थेरेपिस्ट, क्लीनिक, अस्पताल और बचपन से लेकर वर्तमान स्वास्थ्य स्थिति का विस्तृत व सम्पूर्ण ब्यौरा आशय पत्र के अनुभागों के बारे में अधिक जानकारी के लिए इस लिंक पर क्लिक करें- https://nayi-disha.org/hi/article/letter-intent-your-child-special-needs/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Letter of Intent* A LOI as it is known is not a legal document but a description about your child’s life and vision. This one document passes on vital information about your child to the future caretaker(s). You can include the following sections to your letter of intent:- *1)* Family History- Details about child’s birth, place of residence, school, relatives and parents’ vision for the child *2)* Living- Overview about your child’s living, daily routine, affairs, habits, likes and dislikes *3)* Education and employment- Details about current education of the child, special classes, special schools, recreational/extracurricular activities, vocational trainings. *4)* Health Care- Details about current health condition of the child, with detailed history of the child’s healthcare since birth. Specific names of doctors, therapists, clinics, hospitals etc. may be included in this section for future reference. For more information on sections of letter of intent, click on this link 👉 https://www.nayi-disha.org/article/letter-intent-your-child-special-needs"
          ]
        }
      }
    },
    21 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Letter of Intent* You can further add these sections to your letter of intent:- *1)* Behaviors- Understanding of child’s behaviour, child’s likes, dislikes, preferred company among friends and family and specific behavior management strategies *2)* Religious environment- Details about a particular religious/spiritual interest that the child *3)* Social environment- Specifications regarding places that the child may like visiting. *4)* Residential needs: Details of specifications about the future place of residence for your child. *5)* Final provision: Describe your wish for the final arrangement of the child. Type of funeral, religious service, burial or any other aspect *6)* Financial information: Details of financial planning for the child. It will be helpful to describe overview of assets that child will inherit, and how you would like them to be utilized by/for the child"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*विशिष्ट उद्देश्य पत्र (लेटर ऑफ़ इंटेंट)* एक सामान्य विशिष्ट उद्देश्य पत्र को इन निम्न अनुभागों में भी बांट सकते है:- *१)* बच्चे का व्यवहार- बच्चे की परिवार और मित्रो संबंधी पसंद, नापसंद और प्राथमिकताओं को स्पष्ट रूप से बताया जाना चाहिए *२)* धार्मिक वातावरण- विशिष्ट धार्मिक/आध्यात्मिक माहौल और रुचियों का विवरण *३)* सामाजिक वातावरण- बच्चा किस प्रकार के सामाजिक स्थलों पर जाना पसंद करता है *४)* निवास स्थान की जरूरतें- वह स्थान जहां बच्चा रोज़ जाने या रहने में असहज महसूस कर सकता है *५)* अंतिम प्रावधान- अंतिम समय में अपने बच्चे के लिए किस तरह की व्यवस्था आप चाहती/चाहते हैं *६)* धन-संपत्ति संबंधी जानकारी-बच्चे के लिए यदि किसी प्रकार की वित्तीय योजना को बनाया गया है तो उसको स्पष्ट रूप से यहाँ बताएं"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Letter of Intent* You can further add these sections to your letter of intent:- *1)* Behaviors- Understanding of child’s behaviour, child’s likes, dislikes, preferred company among friends and family and specific behavior management strategies *2)* Religious environment- Details about a particular religious/spiritual interest that the child *3)* Social environment- Specifications regarding places that the child may like visiting. *4)* Residential needs: Details of specifications about the future place of residence for your child. *5)* Final provision: Describe your wish for the final arrangement of the child. Type of funeral, religious service, burial or any other aspect *6)* Financial information: Details of financial planning for the child. It will be helpful to describe overview of assets that child will inherit, and how you would like them to be utilized by/for the child"
          ]
        }
      }
    },
    22 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "These are the key points to be considered before Financial Planning for your child *1.* *Lifetime support*- This is with regard to both personal and financial matters. Your involvement is not restricted to a couple of years till he/she starts becoming financially independent, as is the case in a typical scenario. *2.* *Expenses* pile on due to services availed such as inclusive education, rehabilitation and recreation, support requirements in the form of regular therapies. Making ends meet to meet these expenses is hard, but not impossible if a good planning practise is in place. *3.* *Retirement savings* -Parents must assess their pension income and retirement savings, and study if it would meet the future lifetime expenses of their own selves and their dependent child. *4.* *Estate Planning* -Understanding the mode of distribution of assets for your loved ones, setting up legal guardianship, formation of a trust, writing a Will are issues which need to be addressed. For more information on sections of financial planning, click on this link 👉 https://nayi-disha.org/article/financial-planning-your-child-special-needs-future-planning-essential-and-urgent/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*आपके बच्चे के भविष्य के लिए वित्तीय योजना एक आवश्यकता है।* वित्तीय योजना बनाते समय, निम्नलिखित चार पॉइंट्स ध्यान में रखे:- *१)* आपकी भागीदारी, बच्चे के व्यक्तिगत और वित्तीय मामलों में, उसके पूरे जीवन काल में होगी।आपकी भूमिका आपके बच्चे के जीवन में कुछ ही साल के लिए प्रतिबंधित नहीं है। *२)* आपके बच्चे पर रोज़ाना खर्च मेहेंगा हो सकता है पर इसका अर्थ यह नहीं है की एक उत्तम वित्तीय योजना बनाना असंभव है। *३)* सेवा निवृत्ति की जमा पूँजी और पेंशन केवल आपके रोज़ के खर्च के लिए ही नहीं पर आपके बच्चे की देख रेख के लिए भी है। निवृत्ति के बाद की योजना उसी हिसाब से बनाये। *४)* जायदाद के प्रति योजना बच्चे के भविष्य के लिए बहुत आवश्यक हो सकता है। यह ट्रस्ट, गरदिअनशिप एंड वसीयत को बनाते समय यह ध्यान में रखे।"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "These are the key points to be considered before Financial Planning for your child *1.* *Lifetime support*- This is with regard to both personal and financial matters. Your involvement is not restricted to a couple of years till he/she starts becoming financially independent, as is the case in a typical scenario. *2.* *Expenses* pile on due to services availed such as inclusive education, rehabilitation and recreation, support requirements in the form of regular therapies. Making ends meet to meet these expenses is hard, but not impossible if a good planning practise is in place. *3.* *Retirement savings* -Parents must assess their pension income and retirement savings, and study if it would meet the future lifetime expenses of their own selves and their dependent child. *4.* *Estate Planning* -Understanding the mode of distribution of assets for your loved ones, setting up legal guardianship, formation of a trust, writing a Will are issues which need to be addressed. For more information on sections of financial planning, click on this link 👉 https://nayi-disha.org/article/financial-planning-your-child-special-needs-future-planning-essential-and-urgent/"
          ]
        }
      }
    },
    23 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*Financial Planning* Start thinking about financial planning for your special child. For more information on sections of letter of intent, click on this link 👉 https://nayi-disha.org/article/start-thinking-about-financial-planning-your-special-child/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*वित्तीय योजना* अपने बच्चे के लिए फाइनेंशियल प्लानिंग के बारे में सोचना शुरू करें। आशय पत्र के अनुभागों के बारे में अधिक जानकारी के लिए, इस लिंक पर क्लिक करें 👉 https://nayi-disha.org/hi/article/start-thinking-about-financial-planning-your-special-child/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*Financial Planning* Start thinking about financial planning for your special child. For more information on sections of letter of intent, click on this link 👉 https://nayi-disha.org/article/start-thinking-about-financial-planning-your-special-child/"
          ]
        }
      }
    },
    24 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about understanding the role of individuals in your legal documents"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["आपके कानूनी दस्तावेजों में व्यक्तियों की भूमिका को समझने के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about understanding the role of individuals in your legal documents"],
        }
      }
    },
    25 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about understanding distribution of financial affairs for child's care"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["बच्चे की देखभाल के लिए वित्तीय मामलों के वितरण को समझने के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about understanding distribution of financial affairs for child's care"],
        }
      }
    },
    26 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "*8 Point Plan To Secure Your Child’s Finances* *1.* Review your personal assets *2.* Draft a Letter of Intent *3.* Find a financial advisor *4.* Assign legal roles to individuals in your child’s life *5.* Write a will. *6.* Settlor forms the trust. *7.* Apply for guardianship. Give the letter of intent (LOI) *8.* Inform near and dear about will, letter of intent, trust and guardianship Please find the 8 Point Plan to Secure Your Child's Finances in the link here 👉 https://storage.googleapis.com/ndrc_support_bucket/8Pointsteptosecurechild'sfutureposter9.png"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "अपने बच्चे के वित्त सुरक्षित रखने के लिए आठ सीढ़ी योजना *१)* अपनी सारी सम्पत्तियों की समीक्षा करे *२)* विशिष्ट उद्देश्य पत्र ( लेटर ऑफ़ इंटेंट) बनाये *३)* एक वित्तीय सलाहकार ढूंढे जो वित्तीय और जायदाद के मामलों के साथ साथ चार्टर्ड अकाउंटेंट (सी.ऐ.) की भी भूमिका निभा सके *४)* वसीयत प्रबंदक (विल एक्सीक्यूटर), व्यवस्थापक (सेट्लर), ट्रस्टी और पालक जैसे पदों के व्यक्तित्यों को नियुक्त करे *५)* अपनी वसीयत लिखिए *६)* व्यवस्थापक (सेट्लर) ट्रस्ट की स्थापना करता है *७)* गार्डियनशिप के लिए आवेदन करे और पालक को विशिष्ट उद्देश्य पत्र ( लेटर ऑफ़ इंटेंट) सौपें *८)* अपने करीबी रिश्तेदार और मित्रो को पालक, लेटर ऑफ़ इंटेंट, वसीयत और ट्रस्ट के बारे में सूचित करे। कृपया यहां दिए गए लिंक में अपने बच्चे के वित्त को सुरक्षित करने के लिए 8 सीडी योजना देखें 👉 https://storage.googleapis.com/ndrc_support_bucket/अपने_बच्चे_के_वित्त_सुरक्षित_रखने_के_लिए_आठ_सीढ़ी_योजना.pdf"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "*8 Point Plan To Secure Your Child’s Finances* *1.* Review your personal assets *2.* Draft a Letter of Intent *3.* Find a financial advisor *4.* Assign legal roles to individuals in your child’s life *5.* Write a will. *6.* Settlor forms the trust. *7.* Apply for guardianship. Give the letter of intent (LOI) *8.* Inform near and dear about will, letter of intent, trust and guardianship Please find the 8 Point Plan to Secure Your Child's Finances in the link here 👉 https://storage.googleapis.com/ndrc_support_bucket/8Pointsteptosecurechild'sfutureposter9.png"
          ]
        }
      }
    },
    27 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Here are some points to help you get started when planning a will for your family- Part 1 *1)* Prepare a list of all your assets and property after taking into account all your debts, liabilities and expenses. *2)* Identify how you wish to distribute the assets i.e. who will be the beneficiary for which asset *3)* Mention the disability of your child clearly in the Will *4)* If you would like to leave a larger share for your child with special needs, please identify the amount, item or share clearly. State if you would want this inheritance to go to the Trust when formed? List the specific item(s) that will go to the Trust through the Will? For more information please click on this link  👉 https://nayi-disha.org/article/tips-writing-will-child-special-needs/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "वसीयत बनाने के कुछ सुझाव- पार्ट १ *१)* अपनी वसीयत में बच्चे की विशेष जरूरत (डिसेबिलिटी प्रमाणपत्र के आधार पर )और असमर्थता खासकर वित्ययी मामलों को लेकर इसका स्पष्ट उल्लेख करें *२)* यदि आप अपने विशेष जरूरतों वाले बच्चे के नाम पर संपत्ति का बड़ा हिस्सा छोड़ना चाहते हैं तो कृपया इस विषय को स्पष्ट रूप से बताएं। यह भी बताएं, कि क्या आप चाहते हैं कि ट्रस्ट के बनने पर यह संपत्ति उसमें चली जाये? एक लिस्ट में उन सभी चल और अचल संपत्ति के बारे में लिखे जो वसीयत के माध्यम से ट्रस्ट के अधिकार में दी जाएंगी। *३)* यदि आप परिवार के किसी सदस्य को संपत्ति का उत्तराधिकारी नहीं बनाना चाहते, तो इस बात का वर्णन करें और स्पष्ठ रूप से इसका कारण बताएं। *४)* वसीयत में निर्धारित किए गए नियम के अनुसार क्या परिवार के दूसरे सदस्य सीधे ही संपत्ति के उतराधिकारी बनेंगे या इसे भी ट्रस्ट के माध्यम से प्राप्त किया जाएगा? वसीयत में इस बात को स्पष्ट करें।"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Here are some points to help you get started when planning a will for your family- Part 1 *1)* Prepare a list of all your assets and property after taking into account all your debts, liabilities and expenses. *2)* Identify how you wish to distribute the assets i.e. who will be the beneficiary for which asset *3)* Mention the disability of your child clearly in the Will *4)* If you would like to leave a larger share for your child with special needs, please identify the amount, item or share clearly. State if you would want this inheritance to go to the Trust when formed? List the specific item(s) that will go to the Trust through the Will? For more information please click on this link  👉 https://nayi-disha.org/article/tips-writing-will-child-special-needs/"
          ]
        }
      }
    },
    28 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Here are some points to help you get started when planning a will for your family - Part 2 *1)* If you leave more for the special child, clearly state the reasons How will the remainder of your assets be distributed among your other family members such as your Spouse, other children or other causes (Charities, if applicable)? *2)* If you wish to disinherit any family members, state the reason clearly why you want to do so? *3)* Will other family members acquire inheritance directly or through the Trust. Stipulate that in the Will. *4)* Will your other children receive their inheritance immediately on your death or at some future time and how? Whom do you want to assign to manage their estate till they reach 18?"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "वसीयत बनाने के कुछ सुझाव- पार्ट २ *१)* जब तक आपका बच्चा/बच्ची 18 वर्ष की आयु तक नहीं पहुँचते हैं, तब तक आप उनकी संपत्ति की देखभाल का अधिकार किसे देना चाहेंगे? इसका स्पष्ट उल्लेख करें । *२)* विशिष्ट ज़रुरत वाले बच्चे को 18 साल की उम्र के बाद भी अभिभावक की ज़रुरत होगी I माता पिता पहले अभिभावक होते हैं मगर आपकी मृत्य के पश्चात कौन इस बच्चे का अभिभावक बनेगा इसका निर्णय ले कर इसका उल्लेख वसीहत में स्पष्ट करें। *३)* यदि आपके किसी बच्चे की मृत्यु हो जाती है, इस स्थिति में क्या आप संपत्ति में उसके हिस्से को, उसके या फिर अपने दूसरे बच्चों को देना चाहते हैं या फिर इसके लिए दूसरे कानूनी दावेदार जैसे जीवनसाथी या फिर दूसरे भाई-बहन को देना चाहेंगे? *४)* बच्चे के किस उम्र में आप यह सुनिश्चित करना चाहेंगे कि उन्हें आपकी सम्पत्ति प्राप्त होगी।"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Here are some points to help you get started when planning a will for your family - Part 2 *1)* If you leave more for the special child, clearly state the reasons How will the remainder of your assets be distributed among your other family members such as your Spouse, other children or other causes (Charities, if applicable)? *2)* If you wish to disinherit any family members, state the reason clearly why you want to do so? *3)* Will other family members acquire inheritance directly or through the Trust. Stipulate that in the Will. *4)* Will your other children receive their inheritance immediately on your death or at some future time and how? Whom do you want to assign to manage their estate till they reach 18?"
          ]
        }
      }
    },
    29 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "Here are some points to help you get started when planning a will for your family- Part 3 *1)* At what age do I ensure my child receives his/her inheritance? *2)* How will the funds be provided for managing your special child’s expenses by the caretaker when taking over financial duties from you? *3)* Make your intentions clear in the Will and do not keep any ambiguous clause. Avoid irreconcilable clauses in the Will, otherwise the last known Will shall prevail. *4)* Will the child’s appointed Guardian only manage personal affairs or financial affairs too? Make sure you have the consent of the guardian to act! *5)* Make sure to take the help of a professional to get it certified"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "वसीयत बनाने के कुछ सुझाव- पार्ट ३ *१)* वसीयत को बनाते समय अपनी सभी इच्छाएँ और मर्ज़ी स्पष्ट रूप से लिखें और कहीं भी किसी प्रकार का कोई असपष्ट या अनेक अर्थ वाला वाक्य नहीं लिखें नहीं तो आखिरी स्पष्ट लिखी वसीयत ही जारी मानी जाएगी। *२)* आपकी मृत्य होने पर कौन आपकी वसीहत को संचालित करेगा इसकी नियुक्ति करें *३)* जो व्यक्ति इस वसीयत को संचालित करेगा, उसे इसके बने होने की जानकारी जरूर दें जिससे वसीयत के होने का पता रहेगा I *४)* किसी भी प्रकार का परिवर्तन होने की स्थिति में वसीयत को प्रत्येक 3-4 वर्ष बाद इस परिवर्तन के साथ दोबारा अवश्य लिखें *५)* आपने जो कुछ लिखा है उसको प्रमाणित करवाने के लिए किसी पेशेवर व्यक्ति की मदद जरूर लें।"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "Here are some points to help you get started when planning a will for your family- Part 3 *1)* At what age do I ensure my child receives his/her inheritance? *2)* How will the funds be provided for managing your special child’s expenses by the caretaker when taking over financial duties from you? *3)* Make your intentions clear in the Will and do not keep any ambiguous clause. Avoid irreconcilable clauses in the Will, otherwise the last known Will shall prevail. *4)* Will the child’s appointed Guardian only manage personal affairs or financial affairs too? Make sure you have the consent of the guardian to act! *5)* Make sure to take the help of a professional to get it certified"
          ]
        }
      }
    },
    30 => %{
      hsm_uuid: @parent_hsm_uuid_poster_eng,
      variables: ["is about keep trying something new"],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_poster_hn,
          variables: ["कुछ नया करने की कोशिश करते रहने के बारे में है"],
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_poster_eng,
          variables: ["is about keep trying something new"],
        }
      }
    },
    31 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "How to find a suitable trustee for your Special Needs Trust? Factors to consider while identifying a suitable trustee: The trustee should be competent enough to manage accounts, taxation, investments and other financial affairs. The trustee should be a person who can put the beneficiary interest on the top. The trustees are going to work for the beneficiary and so it’s important that they understand his/her requirement well. Individual Or Corporate Trustees- If all trustees are identified as individuals then it has to be seen how they will bring changes in their life. Contrary to this professional trustee may be well experienced to manage the affairs of the beneficiary. Though most families prefer friends and other family members as successor trustees, globally professional trustees have seen outperforming family members since they have adequate knowledge and experience. Even if the professional trustee is involved the family members have to be there in a guiding role. For more information, click on this link 👉 https://nayi-disha.org/article/how-find-suitable-trustee-your-special-needs-trust/"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*विश्वसनीय ट्रस्टी कैसे ढूंढे?* 🤔 *१)* जो हिसाब किताब, पूँजी निवेश और कर (टैक्स) सम्बंधित मामलों में विशेषज्ञ हो 💵 *२)* जो विकलांग बच्चे की ज़रूरतों को समझे और औरो से भी बना के रखे 🚸 *३)* जो लाभार्थी के ज़रूरतों को प्राथमिकता दे और ट्रस्ट का फायदा न उठाय 👶 *४)* एक व्यक्ति और कॉर्पोरेट (जिसको ट्रस्ट सँभालने का ज़्यादा अनुभव हो सकता है) ट्रस्टी में चुने 👥 *५)* मित्र और रिश्तेदार भी ट्रस्टी हो सकते है। यह जांचे की उनको ट्रस्टी के पद की कितनी जानकारी है। 📚 अधिक जानकारी के लिए यह लिंक दबाए 👉 https://nayi-disha.org/hi/article/how-find-suitable-trustee-your-special-needs-trust/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "How to find a suitable trustee for your Special Needs Trust? Factors to consider while identifying a suitable trustee: The trustee should be competent enough to manage accounts, taxation, investments and other financial affairs. The trustee should be a person who can put the beneficiary interest on the top. The trustees are going to work for the beneficiary and so it’s important that they understand his/her requirement well. Individual Or Corporate Trustees- If all trustees are identified as individuals then it has to be seen how they will bring changes in their life. Contrary to this professional trustee may be well experienced to manage the affairs of the beneficiary. Though most families prefer friends and other family members as successor trustees, globally professional trustees have seen outperforming family members since they have adequate knowledge and experience. Even if the professional trustee is involved the family members have to be there in a guiding role. For more information, click on this link 👉 https://nayi-disha.org/article/how-find-suitable-trustee-your-special-needs-trust/"
          ]
        }
      }
    },
    32 => %{
      hsm_uuid: @parent_hsm_uuid_advise_eng,
      variables: [
        "A trust is a legal agreement for management, preservation and upkeep of the child who is the benefactor of the Trust. The Trust deed defines the objective, power of trustees (people managing the trust), management, preservation and distribution of income to the child. It gives the child ongoing financial support for his/her medical and lifestyle requirements. A Trust being an independent separate legal entity is not impacted by any eventualities in the personal life of the child’s parents/caregivers. Any parent with a child with special needs can set up a private trust and secure the future of the child. This Trust can fund all expenses related to child care. The Settler of the Trust (person creating the trust) can specify how the funds should be utilized. For more information on *Setting up a Trust* click on this link  👉  https://www.nayi-disha.org/article/setting-trust-my-child-financial-planning-my-special-child"
      ],
      translations: %{
        "hi" => %{
          hsm_uuid: @parent_hsm_uuid_advise_hn,
          variables: [
            "*बच्चे के लिए ट्रस्ट का महत्व* ट्रस्ट बच्चे के मेडिकल और जीवन शैली ज़रूरतों के लिए अविरत वित्तीय सहारा प्रदान करता है । ट्रस्ट की कानूनी अस्तित्व अलग और स्वाधीन होती है । माता पिता प्राइवेट ट्रस्ट द्वारा अपने विकलांग बच्चे का भविष्य सुरक्षित कर सकते है। सेट्लर/ व्यवस्थापक उल्लेखित कर सकता है की वित्त का प्रयोग कैसे होगा। ट्रस्ट बच्चे के देख रेख के लिए कानूनी/वैध समझौता होता है (जिसका दानकर्ता भी बच्चा ही होता है ।ट्रस्ट दीड, ट्रस्टी के उद्देश्य, अधिकार, और बच्चे की आय की देख रेख की शर्ते स्पष्ट करता है ।*एक विकलांग बच्चे के लिए स्थिर (इररेवोकेबल) प्राइवेट ट्रस्ट सबसे उपयुक्त होता है |* अधिक जानकारी के लिए यह लिंक दबाए 👉 https://nayi-disha.org/hi/article/setting-trust-my-child-financial-planning-my-special-child/"
          ]
        },
        "en" => %{
          hsm_uuid: @parent_hsm_uuid_advise_eng,
          variables: [
            "A trust is a legal agreement for management, preservation and upkeep of the child who is the benefactor of the Trust. The Trust deed defines the objective, power of trustees (people managing the trust), management, preservation and distribution of income to the child. It gives the child ongoing financial support for his/her medical and lifestyle requirements. A Trust being an independent separate legal entity is not impacted by any eventualities in the personal life of the child’s parents/caregivers. Any parent with a child with special needs can set up a private trust and secure the future of the child. This Trust can fund all expenses related to child care. The Settler of the Trust (person creating the trust) can specify how the funds should be utilized. For more information on *Setting up a Trust* click on this link  👉  https://www.nayi-disha.org/article/setting-trust-my-child-financial-planning-my-special-child"
          ]
        }
      }
    }
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec load() :: map()
  def load, do: @hsm
end
